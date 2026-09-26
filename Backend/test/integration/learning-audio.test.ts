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
import { learningAudioFixture } from "../helpers/learning-audio.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "听力 HTTP 鉴权与版本冻结",
  () => {
    let database: DatabaseResource;
    let app: FastifyInstance;
    let repository: LearningEngineRepository;
    let attemptId: string;
    const users = [randomUUID(), randomUUID()];
    const tokens: string[] = [];
    const characterId = randomUUID();
    const unit = learningFixture(`test.audio.${randomUUID()}`);
    const assets = [
      learningAudioFixture(),
      learningAudioFixture("Hello friend.", "M5", 660),
      learningAudioFixture("Tea, please.", "M5", 880),
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
              { deviceId: "audio-test", platform: "ios" },
              {},
            )
          ).accessToken,
        );
      }
      for (const question of unit.questions) {
        const asset =
          question.type === "listeningChoice"
            ? assets[0]
            : question.type === "dictation"
              ? assets[1]
              : undefined;
        if (
          asset &&
          (question.type === "listeningChoice" || question.type === "dictation")
        )
          question.audio = {
            assetId: asset.metadata.id,
            text: asset.metadata.transcript,
            voice: asset.metadata.voice,
          };
      }
      await repository.publishBatch(
        [unit],
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
        await database.sql`delete from app.learning_audio_assets where id=${asset.metadata.id}`;
      await database.close();
    });
    it("只允许本人挑战的听力题，公开响应不含原文或声音配置", async () => {
      const url = `/v1/learning/attempts/${attemptId}/audio/q.listen`;
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
      const response = await app.inject({
        method: "GET",
        url,
        headers: { authorization: `Bearer ${tokens[0] ?? ""}` },
      });
      expect(response.statusCode).toBe(200);
      expect(response.headers["cache-control"]).toBe("no-store");
      expect(response.json()).toMatchObject({
        assetId: assets[0]?.metadata.id,
        byteSize: assets[0]?.bytes.length,
      });
      expect(response.json()).not.toHaveProperty("transcript");
      expect(response.json()).not.toHaveProperty("voice");
      expect(
        (
          await app.inject({
            method: "GET",
            url: `/v1/learning/attempts/${attemptId}/audio/q.choice`,
            headers: { authorization: `Bearer ${tokens[0] ?? ""}` },
          })
        ).statusCode,
      ).toBe(404);
    });
    it("发布新版后，已有挑战继续使用旧版声音", async () => {
      const changed = structuredClone(unit);
      changed.version = 2;
      const question = changed.questions.find((q) => q.type === "listeningChoice");
      const replacement = assets[2];
      if (question?.type !== "listeningChoice" || !replacement)
        throw new Error("缺少听力测试资料。");
      question.audio = {
        assetId: replacement.metadata.id,
        text: replacement.metadata.transcript,
        voice: replacement.metadata.voice,
      };
      await repository.publishBatch(
        [changed],
        assets.map((asset) => asset.metadata),
      );
      const response = await app.inject({
        method: "GET",
        url: `/v1/learning/attempts/${attemptId}/audio/q.listen`,
        headers: { authorization: `Bearer ${tokens[0] ?? ""}` },
      });
      expect(response.statusCode).toBe(200);
      expect(response.json()).toMatchObject({ assetId: assets[0]?.metadata.id });
      await expect(
        repository.publishBatch(
          [
            {
              ...changed,
              version: 3,
              questions: changed.questions.map((q) =>
                q.type === "listeningChoice"
                  ? { ...q, audio: { ...q.audio, text: "不匹配" } }
                  : q,
              ),
            },
          ],
          [],
        ),
      ).rejects.toMatchObject({ code: "LEARNING_AUDIO_NOT_READY" });
    });
  },
);
