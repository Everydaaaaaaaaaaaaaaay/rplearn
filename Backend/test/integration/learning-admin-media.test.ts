import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { LearningAdminRepository } from "../../src/modules/learning/admin-repository.js";
import { LearningAdminService } from "../../src/modules/learning/admin-service.js";
import { registerLearningAdminRoutes } from "../../src/modules/learning/admin-routes.js";
import { LearningGenerationRepository } from "../../src/modules/learning/generation-repository.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { contentHash } from "../../src/modules/learning/content.js";
import { learningFixture } from "../helpers/learning.js";
import { learningAudioFixture } from "../helpers/learning-audio.js";
import { learningImageFixture } from "../helpers/learning-images.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "后台素材鉴权与版本范围",
  () => {
    let app: FastifyInstance, database: DatabaseResource;
    const resources: { app?: FastifyInstance; database?: DatabaseResource } = {};
    const unit = learningFixture(`test.media.${randomUUID()}`);
    const image = learningImageFixture(72),
      otherImage = learningImageFixture(173),
      audio = learningAudioFixture();
    const token = "admin-media-isolated-test-token-not-production";
    const headers = { authorization: `Bearer ${token}` };
    const download = vi.fn<typeof fetch>((input) => {
      const asset = [image, otherImage, audio].find((item) =>
        (typeof input === "string"
          ? input
          : input instanceof URL
            ? input.href
            : input.url
        ).includes(item.metadata.id),
      );
      if (!asset) throw new Error("下载了测试范围外的素材。");
      return Promise.resolve(
        new Response(new Uint8Array(asset.bytes), {
          headers: { "content-type": asset.metadata.contentType },
        }),
      );
    });
    const store = {
      createDownloadUrl: (key: string) =>
        Promise.resolve(`https://storage.example/${key}?signature=temporary`),
    };
    let latest: typeof unit;
    const jobId = randomUUID();
    beforeAll(async () => {
      const config = integrationConfig({
        ADMIN_API_ENABLED: "true",
        ADMIN_API_KEYS: `media-editor=${token}`,
      });
      database = createDatabase(config);
      resources.database = database;
      await runMigrations(database);
      const q = unit.questions[0];
      if (q?.type !== "choice" || !q.options[0]) throw new Error("缺少选择题。");
      q.options[0].imageAssetId = image.metadata.id;
      unit.questions[0] = {
        ...q,
        type: "listeningChoice",
        audio: {
          assetId: audio.metadata.id,
          text: audio.metadata.transcript,
          voice: audio.metadata.voice,
        },
      };
      for (const question of unit.questions) {
        if (question.type === "listeningChoice" || question.type === "dictation") {
          question.audio = {
            assetId: audio.metadata.id,
            text: audio.metadata.transcript,
            voice: audio.metadata.voice,
          };
          if (question.type === "dictation")
            question.acceptedAnswers = [audio.metadata.transcript];
        }
      }
      latest = structuredClone(unit);
      latest.version = 2;
      const newer = latest.questions[0];
      if (newer?.type !== "listeningChoice" || !newer.options[0])
        throw new Error("缺少新版本题目。");
      newer.options[0].imageAssetId = otherImage.metadata.id;
      const repository = new LearningEngineRepository(database);
      await repository.publishBatch(
        [unit],
        [audio.metadata],
        [image.metadata, otherImage.metadata],
      );
      await repository.publish(latest);
      app = await buildApp(config, { logger: false });
      resources.app = app;
      registerLearningAdminRoutes(
        app,
        createAdminAuthenticator(config.adminApiKeys),
        new LearningAdminService(
          new LearningAdminRepository(database),
          new LearningGenerationRepository(database),
          [],
          store,
          download,
        ),
      );
      await app.ready();
    });
    afterAll(async () => {
      if (resources.database)
        await resources.database
          .sql`delete from app.learning_generation_jobs where id=${jobId}`;
      await resources.app?.close();
      if (!resources.database) return;
      await database.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
      await database.sql`delete from app.learning_units where id=${unit.id}`;
      await database.sql`delete from app.learning_audio_assets where id=${audio.metadata.id}`;
      await database.sql`delete from app.learning_image_assets where id=any(${[image.metadata.id, otherImage.metadata.id]}::text[])`;
      await database.close();
    });
    const route = (kind: string, id: string, version = 1, hash = contentHash(unit)) =>
      `/internal/admin/learning/units/${unit.id}/media/${kind}/${id}?version=${String(version)}&hash=${hash}`;
    it("详情只给本版本的审核元数据；鉴权后可读取冻结版本音频和图片", async () => {
      const detail = (
        await app.inject({
          url: `/internal/admin/learning/units/${unit.id}?version=1`,
          headers,
        })
      ).json<{ media: { images: unknown[]; audio: unknown[] }; mediaHash?: string }>();
      expect(detail.media).toEqual({
        images: [image.metadata],
        audio: [audio.metadata],
      });
      for (const [kind, asset] of [
        ["images", image],
        ["audio", audio],
      ] as const) {
        const url = route(kind, asset.metadata.id);
        expect((await app.inject({ url })).statusCode).toBe(401);
        expect(
          (await app.inject({ url, headers: { authorization: "Bearer wrong" } }))
            .statusCode,
        ).toBe(401);
        const response = await app.inject({ url, headers });
        expect(response.statusCode).toBe(200);
        expect(response.rawPayload).toEqual(asset.bytes);
        expect(response.headers["cache-control"]).toBe("no-store");
        expect(response.headers["x-content-type-options"]).toBe("nosniff");
        expect(response.headers["content-type"]).toBe(asset.metadata.contentType);
      }
    });
    it("拒绝未引用素材、错误类型、过期内容哈希和不存在版本，不访问对象存储", async () => {
      download.mockClear();
      for (const [url, status] of [
        [route("images", otherImage.metadata.id), 404],
        [route("audio", image.metadata.id), 404],
        [route("images", image.metadata.id, 2, contentHash(latest)), 404],
        [route("images", image.metadata.id, 2), 409],
        [route("images", image.metadata.id, 3), 404],
        [route("images", image.metadata.id).replace(/&hash=.*/, ""), 400],
      ] as const)
        expect((await app.inject({ url, headers })).statusCode).toBe(status);
      expect(download).not.toHaveBeenCalled();
      expect(
        (
          await app.inject({
            url: route("images", otherImage.metadata.id, 2, contentHash(latest)),
            headers,
          })
        ).statusCode,
      ).toBe(200);
    });
    it("候选素材同样绑定当前稿件哈希，修订后旧请求失效", async () => {
      await database.sql`insert into app.learning_generation_jobs(id,role_key,level_key,status,candidate,candidate_hash) values(${jobId},${unit.roleKey},${unit.level},'review',${JSON.stringify(unit)}::jsonb,${contentHash(unit)})`;
      const detail = (
        await app.inject({ url: `/internal/admin/learning/jobs/${jobId}`, headers })
      ).json<{ media: { images: unknown[]; audio: unknown[] }; mediaHash?: string }>();
      expect(detail.mediaHash).toBe(contentHash(unit));
      expect(detail.media.images).toEqual([image.metadata]);
      const url = `/internal/admin/learning/jobs/${jobId}/media/images/${image.metadata.id}?hash=${contentHash(unit)}`;
      expect((await app.inject({ url, headers })).statusCode).toBe(200);
      await database.sql`update app.learning_generation_jobs set candidate=${JSON.stringify(latest)}::jsonb,candidate_hash=${contentHash(latest)} where id=${jobId}`;
      download.mockClear();
      expect((await app.inject({ url, headers })).statusCode).toBe(409);
      expect(download).not.toHaveBeenCalled();
    });
  },
);
