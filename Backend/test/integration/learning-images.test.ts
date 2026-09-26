import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { createLearningService } from "../../src/modules/learning/service.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { learningImageFixture } from "../helpers/learning-images.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "图片 HTTP 鉴权与版本冻结",
  () => {
    let database: DatabaseResource;
    let app: FastifyInstance;
    let repository: LearningEngineRepository;
    let attemptId: string;
    const users = [randomUUID(), randomUUID()];
    const tokens: string[] = [];
    const characterId = randomUUID();
    const unit = learningFixture(`test.image.${randomUUID()}`);
    const assets = [
      learningImageFixture(60),
      learningImageFixture(120),
      learningImageFixture(180),
    ];
    const download = vi.fn((key: string) =>
      Promise.resolve(`https://assets.example.com/${key}?signature=temporary`),
    );
    beforeAll(async () => {
      const config = integrationConfig();
      database = createDatabase(config);
      await runMigrations(database);
      repository = new LearningEngineRepository(database);
      const auth = await createAuthService(config, database);
      for (const user of users) {
        await database.sql`insert into app.users(id) values(${user})`;
        tokens.push(
          (
            await auth.loginFederated(
              user,
              0,
              { deviceId: "image-test", platform: "ios" },
              {},
            )
          ).accessToken,
        );
      }
      const question = unit.questions[0];
      if (question?.type !== "choice" || !question.options[0] || !assets[0])
        throw new Error("缺少测试题目。");
      question.options[0].imageAssetId = assets[0].metadata.id;
      await repository.publishBatch(
        [unit],
        undefined,
        assets.map((asset) => asset.metadata),
      );
      const user = users[0];
      if (!user) throw new Error("缺少测试账号。");
      const started = await repository.command(
        user,
        randomUUID(),
        "fixture",
        {},
        async (session) => {
          const state = await session.ensureCharacter(characterId, unit.roleKey);
          await session.recordMessage({
            characterId,
            cycleId: state.cycleId,
            messageId: randomUUID(),
            text: "a".repeat(1000),
          });
          return session.start(characterId, "primary3");
        },
      );
      if (!started.attempt) throw new Error("缺少测试挑战。");
      attemptId = started.attempt.id;
      app = await buildApp(config, { logger: false });
      registerLearningRoutes(
        app,
        auth,
        createLearningService(
          database,
          {
            profile: () => Promise.resolve("primary3"),
            character: () => Promise.resolve(unit.roleKey),
          },
          undefined,
          {
            createDownloadUrl: download,
            createUploadUrl: vi.fn(),
            headObject: vi.fn(),
          },
        ),
      );
    });
    afterAll(async () => {
      await app.close();
      for (const user of users) {
        await database.sql`delete from app.auth_security_events where user_id=${user}`;
        await database.sql`delete from app.users where id=${user}`;
      }
      await database.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
      await database.sql`delete from app.learning_units where id=${unit.id}`;
      for (const asset of assets)
        await database.sql`delete from app.learning_image_assets where id=${asset.metadata.id}`;
      await database.close();
    });
    it("只允许本人挑战实际引用的图片，响应不含审核及来源信息", async () => {
      download.mockClear();
      const url = `/v1/learning/attempts/${attemptId}/images/q.choice/${assets[0]?.metadata.id ?? ""}`;
      expect((await app.inject({ method: "GET", url })).statusCode).toBe(401);
      expect(
        (
          await app.inject({
            method: "GET",
            url,
            headers: { authorization: `Bearer ${tokens[1] ?? ""}` },
          })
        ).statusCode,
      ).toBe(404);
      expect(download).not.toHaveBeenCalled();
      const headers = { authorization: `Bearer ${tokens[0] ?? ""}` };
      for (const invalid of [
        url.replace("q.choice", "q.match"),
        url.replace(assets[0]?.metadata.id ?? "", assets[1]?.metadata.id ?? ""),
      ]) {
        expect(
          (await app.inject({ method: "GET", url: invalid, headers })).statusCode,
        ).toBe(404);
      }
      expect(download).not.toHaveBeenCalled();
      const response = await app.inject({ method: "GET", url, headers });
      expect(response.statusCode).toBe(200);
      expect(response.headers["cache-control"]).toBe("no-store");
      expect(response.json()).toMatchObject({
        assetId: assets[0]?.metadata.id,
        byteSize: assets[0]?.bytes.length,
        width: 128,
        height: 128,
      });
      for (const field of ["description", "source", "reviewedBy", "reviewNotes"])
        expect(response.json()).not.toHaveProperty(field);
    });
    it("新版换图不会影响旧挑战，普通和后台发布入口都拒绝缺失资源", async () => {
      const changed = structuredClone(unit);
      changed.version = 2;
      const question = changed.questions[0];
      if (question?.type !== "choice" || !question.options[0] || !assets[1])
        throw new Error("缺少测试题目。");
      question.options[0].imageAssetId = assets[1].metadata.id;
      await repository.publish(changed);
      const headers = { authorization: `Bearer ${tokens[0] ?? ""}` };
      const base = `/v1/learning/attempts/${attemptId}/images/q.choice/`;
      expect(
        (
          await app.inject({
            method: "GET",
            url: base + (assets[0]?.metadata.id ?? ""),
            headers,
          })
        ).statusCode,
      ).toBe(200);
      expect(
        (
          await app.inject({
            method: "GET",
            url: base + assets[1].metadata.id,
            headers,
          })
        ).statusCode,
      ).toBe(404);
      changed.version = 3;
      question.options[0].imageAssetId = `image.${"a".repeat(64)}`;
      await expect(repository.publish(changed)).rejects.toMatchObject({
        code: "LEARNING_IMAGE_NOT_READY",
      });
      await expect(
        database.sql.begin((sql) => repository.publishInTransaction(sql, changed)),
      ).rejects.toMatchObject({ code: "LEARNING_IMAGE_NOT_READY" });
      const fresh = learningImageFixture(240);
      await expect(
        repository.publishBatch([changed], undefined, [fresh.metadata]),
      ).rejects.toMatchObject({ code: "LEARNING_IMAGE_NOT_READY" });
      expect(
        await database.sql`select id from app.learning_image_assets where id=${fresh.metadata.id}`,
      ).toHaveLength(0);
      await expect(
        repository.publishBatch([unit], undefined, [
          { ...assets[1].metadata, description: "未经重新审核的图片描述。" },
        ]),
      ).rejects.toMatchObject({ code: "LEARNING_IMMUTABLE_IMAGE" });
    });
  },
);
