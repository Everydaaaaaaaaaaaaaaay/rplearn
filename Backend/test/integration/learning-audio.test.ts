import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { createLearningService } from "../../src/modules/learning/service.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { learningAudioFixture } from "../helpers/learning-audio.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "十八题挑战、听力 HTTP 鉴权与版本冻结",
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
      learningAudioFixture("I am Oliver.", "M5", 550),
    ];
    // 只测试多人元数据、授权与冻结；波形夹具不代表真实对话录音。
    const dialogue = assets[0];
    if (!dialogue) throw new Error("缺少对话素材夹具。");
    dialogue.metadata.speakers = [
      { id: "a", voice: "M5" },
      { id: "b", voice: "F3" },
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
      const sort = unit.questions[2];
      const orderingAudio = assets[3];
      if (sort?.type !== "arrange" || !orderingAudio)
        throw new Error("缺少听后排序夹具。");
      unit.questions[2] = {
        ...sort,
        type: "audioArrange",
        audio: {
          assetId: orderingAudio.metadata.id,
          text: orderingAudio.metadata.transcript,
          voice: orderingAudio.metadata.voice,
        },
      };
      const seed = unit.questions[0];
      if (!seed) throw new Error("缺少长卷夹具。");
      // 测试数据仅用于十八次提交与补答边界，不会导入正式教学目录。
      for (let index = 6; index < 18; index++)
        unit.questions.push({ ...seed, id: `test.extra${String(index)}` });
      unit.questions[6] = {
        id: "test.sound-options",
        type: "audioChoice",
        goalId: seed.goalId,
        instruction: "工程声音选择",
        prompt: "选择工程声音",
        hint: "工程提示",
        explanation: "工程答案解析",
        difficultyReason: "测试独立素材授权与冻结",
        audioOptions: assets.slice(0, 3).map((asset, index) => ({
          id: `sound${index}`,
          audio: {
            assetId: asset.metadata.id,
            text: asset.metadata.transcript,
            voice: asset.metadata.voice,
          },
        })),
        answer: "sound1",
      };
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
      expect(started.attempt.unit.questions).toHaveLength(18);
      expect(started.attempt.round.questionIds).toHaveLength(18);
      expect(started.attempt.unit.questions[2]).toMatchObject({
        type: "audioArrange",
        audio: { assetId: orderingAudio.metadata.id },
      });
      expect(started.attempt.unit.questions[2]).not.toHaveProperty("acceptedOrders");
      expect(started.attempt.unit.questions[2]).not.toHaveProperty("audio.text");
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
      await app?.close();
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
    it("双人归档保持完整，发布后不能改写参与声线", async () => {
      const [row] = await database.sql<
        { metadata: unknown }[]
      >`select metadata from app.learning_audio_assets where id=${dialogue.metadata.id}`;
      expect(row?.metadata).toEqual(dialogue.metadata);
      await expect(
        repository.publishBatch(
          [unit],
          [
            {
              ...dialogue.metadata,
              speakers: [
                { id: "a", voice: "M5" },
                { id: "b", voice: "F2" },
              ],
            },
          ],
        ),
      ).rejects.toMatchObject({ code: "LEARNING_IMMUTABLE_AUDIO" });
    });
    it("听后排序沿用本人冻结题目的音频鉴权，未登记素材不能发布", async () => {
      const url = `/v1/learning/attempts/${attemptId}/audio/q.arrange`;
      expect(
        (
          await app.inject({
            method: "GET",
            url,
            headers: { authorization: `Bearer ${tokens[1] ?? ""}` },
          })
        ).statusCode,
      ).toBe(404);
      const response = await app.inject({
        method: "GET",
        url,
        headers: { authorization: `Bearer ${tokens[0] ?? ""}` },
      });
      expect(response.statusCode).toBe(200);
      expect(response.json()).toMatchObject({ assetId: assets[3]?.metadata.id });
      expect(response.json()).not.toHaveProperty("transcript");
      const invalid = structuredClone(unit);
      invalid.version = 2;
      const question = invalid.questions[2];
      if (question?.type !== "audioArrange") throw new Error("缺少听后排序夹具。");
      question.audio.assetId = "test.unpublished";
      await expect(repository.publishBatch([invalid], [])).rejects.toMatchObject({
        code: "LEARNING_AUDIO_NOT_READY",
      });
    });
    it("独立声音只能逐个读取本人冻结题所引用的资源，遗漏身份不隐式选第一段", async () => {
      const url = `/v1/learning/attempts/${attemptId}/audio/test.sound-options`;
      const headers = { authorization: `Bearer ${tokens[0] ?? ""}` };
      expect((await app.inject({ method: "GET", url, headers })).statusCode).toBe(404);
      for (const asset of assets.slice(0, 3)) {
        const target = `${url}?assetId=${asset.metadata.id}`;
        expect((await app.inject({ method: "GET", url: target })).statusCode).toBe(401);
        expect(
          (
            await app.inject({
              method: "GET",
              url: target,
              headers: { authorization: `Bearer ${tokens[1] ?? ""}` },
            })
          ).statusCode,
        ).toBe(404);
        const response = await app.inject({ method: "GET", url: target, headers });
        expect(response.statusCode).toBe(200);
        expect(response.json()).toMatchObject({ assetId: asset.metadata.id });
        expect(response.json()).not.toHaveProperty("transcript");
      }
      expect(
        (
          await app.inject({
            method: "GET",
            url: `${url}?assetId=${assets[3]!.metadata.id}`,
            headers,
          })
        ).statusCode,
      ).toBe(404);
      expect(
        (await app.inject({ method: "GET", url: `${url}?assetId=invalid`, headers }))
          .statusCode,
      ).toBe(400);
      const invalid = structuredClone(unit);
      invalid.version = 2;
      const q = invalid.questions[6];
      if (q?.type !== "audioChoice") throw new Error("缺少声音选项夹具");
      q.audioOptions[1]!.audio.text = "原文不匹配";
      await expect(repository.publishBatch([invalid], [])).rejects.toMatchObject({
        code: "LEARNING_AUDIO_NOT_READY",
      });
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
      const optionQuestion = changed.questions[6];
      const newSound = assets[3]!;
      if (optionQuestion?.type !== "audioChoice") throw new Error("缺少声音选项夹具");
      optionQuestion.audioOptions[0]!.audio = {
        assetId: newSound.metadata.id,
        text: newSound.metadata.transcript,
        voice: newSound.metadata.voice,
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
      const frozen = await repository.read(users[0]!, (session) =>
        session.attempt(attemptId),
      );
      const again = await repository.read(users[0]!, (session) =>
        session.attempt(attemptId),
      );
      expect(frozen.unit).toEqual(again.unit);
      const publicOptions = frozen.unit.questions.find(
        (q) => q.id === "test.sound-options",
      );
      expect(publicOptions).toMatchObject({
        audioOptions: expect.arrayContaining([
          { id: "sound0", audio: { assetId: assets[0]!.metadata.id } },
          { id: "sound1", audio: { assetId: assets[1]!.metadata.id } },
          { id: "sound2", audio: { assetId: assets[2]!.metadata.id } },
        ]),
      });
      const optionURL = `/v1/learning/attempts/${attemptId}/audio/test.sound-options`;
      const headers = { authorization: `Bearer ${tokens[0] ?? ""}` };
      expect(
        (
          await app.inject({
            method: "GET",
            url: `${optionURL}?assetId=${newSound.metadata.id}`,
            headers,
          })
        ).statusCode,
      ).toBe(404);
      expect(
        (
          await app.inject({
            method: "GET",
            url: `${optionURL}?assetId=${assets[0]!.metadata.id}`,
            headers,
          })
        ).statusCode,
      ).toBe(200);
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
    it("十八题首轮和补答只奖励首次答对，结束才重置当前循环", async () => {
      const user = users[0];
      if (!user) throw new Error("缺少测试账号。");
      const read = () => repository.read(user, (session) => session.attempt(attemptId));
      const original = await read();
      const firstRound = original.round.id;
      for (const question of unit.questions.slice(0, 15)) {
        const requestId = randomUUID();
        const input = {
          attemptId,
          roundId: firstRound,
          questionId: question.id,
          answer: gradeAnswer(question, { kind: "skip" }).solution,
        };
        const saved = await repository.command(
          user,
          requestId,
          "answer",
          input,
          (session) => session.submit(input),
        );
        const replay = await repository.command(
          user,
          requestId,
          "answer",
          input,
          (session) => session.submit(input),
        );
        expect(replay).toEqual(saved);
      }
      expect(
        (await repository.read(user, (session) => session.character(characterId)))
          .characters,
      ).toBe(1000);
      await repository.command(user, randomUUID(), "finish", {}, (session) =>
        session.finish(attemptId, true),
      );
      expect(
        (await repository.read(user, (session) => session.character(characterId)))
          .characters,
      ).toBe(0);
      expect(
        (await repository.read(user, (session) => session.progress()))[0]?.points,
      ).toBe(15);
      const retry = await repository.command(
        user,
        randomUUID(),
        "retry",
        {},
        (session) => session.retry(attemptId),
      );
      expect(retry.round.questionIds).toEqual(
        unit.questions.slice(15).map((q) => q.id),
      );
      expect(retry.unit).toEqual(original.unit);
      for (const question of unit.questions.slice(15)) {
        await repository.command(user, randomUUID(), "answer", {}, (session) =>
          session.submit({
            attemptId,
            roundId: retry.round.id,
            questionId: question.id,
            answer: gradeAnswer(question, { kind: "skip" }).solution,
          }),
        );
      }
      await repository.command(user, randomUUID(), "finish", {}, (session) =>
        session.finish(attemptId, false),
      );
      expect((await read()).correctQuestionIds).toHaveLength(18);
      expect(
        (await repository.read(user, (session) => session.progress()))[0]?.points,
      ).toBe(18);
      expect(
        (await repository.read(user, (session) => session.history(characterId, 10)))
          .items[0],
      ).toMatchObject({ questionCount: 18, correctCount: 18 });
    });
  },
);
