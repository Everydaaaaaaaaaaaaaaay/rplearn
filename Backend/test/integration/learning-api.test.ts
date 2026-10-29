import { registerDomainRoutes } from "../../src/modules/domain/routes.js";
import type { MainlineProgress } from "../../src/modules/domain/mainline.js";
import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import {
  createContentReadService,
  createContentService,
} from "../../src/modules/content/service.js";
import { createContentCursorCodec } from "../../src/modules/content/cursor.js";
import { registerContentRoutes } from "../../src/modules/content/routes.js";
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import {
  createDomainLearningContext,
  createDomainService,
} from "../../src/modules/domain/service.js";
import { createAccountService } from "../../src/modules/account/service.js";
import { learningRoleKey } from "../../src/modules/learning/context.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import {
  createLearningService,
  type LearningService,
} from "../../src/modules/learning/service.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { integrationConfig } from "../helpers/integration.js";
import { createTestJobWorker } from "../helpers/jobs.js";
import { freshLearningFixture, learningFixture } from "../helpers/learning.js";

type Attempt = Awaited<ReturnType<LearningService["attempt"]>>;
type Character = Awaited<ReturnType<LearningService["character"]>>;
interface Tokens {
  userId: string;
  accessToken: string;
}

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "单元学习真实鉴权与 HTTP 合同",
  () => {
    let app: FastifyInstance;
    let database: DatabaseResource;
    let repository: LearningEngineRepository;
    let accounts: Tokens[] = [];
    const characterId = randomUUID();
    const unitIds: string[] = [];
    const config = () => integrationConfig();
    const headers = (account = 0) => ({
      authorization: `Bearer ${accounts[account]?.accessToken ?? ""}`,
    });
    const owner = () => {
      const account = accounts[0];
      if (!account) throw new Error("测试账号未建立。");
      return account.userId;
    };
    const post = (url: string, payload: Record<string, unknown>, account = 0) =>
      app.inject({ method: "POST", url, payload, headers: headers(account) });
    const get = (url: string, account = 0) =>
      app.inject({ method: "GET", url, headers: headers(account) });

    beforeAll(async () => {
      database = createDatabase(config());
      await runMigrations(database);
      repository = new LearningEngineRepository(database);
      const auth = await createAuthService(config(), database);
      const content = createContentReadService(database);
      const profile = createDomainLearningContext(database);
      const service = createLearningService(database, {
        profile: profile.difficulty,
        character: async (sql, userId, id) =>
          learningRoleKey(await content.character(sql, userId, id)),
      });
      app = await buildApp(config(), { logger: false });
      registerAuthRoutes(app, auth);
      registerLearningRoutes(app, auth, service);
      registerDomainRoutes(app, auth, createDomainService(database), {
        enableDebugRoutes: false,
      });
      registerContentRoutes(
        app,
        auth,
        createContentService(
          database,
          createContentCursorCodec(config().authTokenHashPepper),
          createSyncCursorCodec(config().authTokenHashPepper),
        ),
      );
      const tokens = new Map<string, string>();
      const worker = createTestJobWorker(config(), database, {
        sendEmailVerification: (email, token) => {
          tokens.set(email, token);
          return Promise.resolve();
        },
        sendPasswordReset: () => Promise.resolve(),
      });
      accounts = [];
      for (let index = 0; index < 2; index++) {
        const email = `learning-${randomUUID()}@example.com`;
        const password = "Correct Horse Learning 1!";
        const registered = await app.inject({
          method: "POST",
          url: "/v1/auth/register",
          payload: { email, password },
        });
        expect(registered.statusCode).toBe(202);
        expect(await worker.runOnce()).toBe("succeeded");
        const verified = await app.inject({
          method: "POST",
          url: "/v1/auth/email/verify",
          payload: { token: tokens.get(email) },
        });
        expect(verified.statusCode).toBe(204);
        const login = await app.inject({
          method: "POST",
          url: "/v1/auth/login",
          payload: {
            email,
            password,
            device: { deviceId: `learning-test-${String(index)}`, platform: "ios" },
          },
        });
        expect(login.statusCode).toBe(200);
        accounts.push(login.json<Tokens>());
        await createDomainService(database).getSnapshot(login.json<Tokens>().userId);
      }
      const synced = await post("/v1/content/commands", {
        commands: [
          {
            commandId: randomUUID(),
            expectedVersion: 0,
            operation: "upsert",
            parentId: null,
            resourceId: characterId,
            resourceType: "character",
            payload: {
              schemaVersion: 1,
              isMainCharacter: true,
              isFriend: true,
              difficulty: "senior3",
              metAt: new Date().toISOString(),
              card: {
                name: "Oliver Bennett",
                age: 28,
                appearance: "测试外貌",
                gender: "male",
                hobbies: ["books"],
                nationality: "British",
                occupation: "Bookshop owner",
                personality: "测试性格",
                regionId: "london",
              },
            },
          },
        ],
      });
      expect(synced.statusCode).toBe(200);
      expect(synced.json<{ results: { status: string }[] }>().results[0]?.status).toBe(
        "applied",
      );
      const domain = createDomainService(database);
      const snapshot = await domain.getSnapshot(owner());
      await domain.updateProfile(owner(), randomUUID(), {
        difficulty: "primary3",
        expectedVersion: snapshot.profile.version,
      });
      for (let i = 0; i < 3; i++) {
        const unit = freshLearningFixture(`test.api-${randomUUID()}`);
        unitIds.push(unit.id);
        await repository.publish(unit);
      }
    });
    afterAll(async () => {
      await app.close();
      for (const account of accounts) {
        await database.sql`delete from app.jobs where user_id=${account.userId}`;
        await database.sql`delete from app.auth_security_events where user_id=${account.userId}`;
        await database.sql`delete from app.users where id=${account.userId}`;
      }
      for (const id of unitIds) {
        await database.sql`delete from app.learning_unit_versions where unit_id=${id}`;
        await database.sql`delete from app.learning_units where id=${id}`;
      }
      await database.sql`delete from app.learning_generation_jobs where role_key='oliver'`;
      await database.close();
    });
    async function fill() {
      const response = await get(`/v1/learning/characters/${characterId}`);
      expect(response.statusCode).toBe(200);
      const state = response.json<Character>();
      const input = {
        characterId,
        cycleId: state.cycleId,
        messageId: randomUUID(),
        text: "a".repeat(1000),
      };
      // 此处只验证 HTTP/事务边界；可信聊天事件接入由独立链路测试证明。
      await repository.command(owner(), randomUUID(), "test.fill", input, (session) =>
        session.recordMessage(input),
      );
    }

    it("鉴权、账号隔离、严格请求合同与旧接口下线", async () => {
      expect((await app.inject({ url: "/v1/learning/journey" })).statusCode).toBe(401);
      expect((await get(`/v1/learning/characters/${characterId}`, 1)).statusCode).toBe(
        404,
      );
      expect((await get("/v1/learning/state")).statusCode).toBe(404);
      expect(
        (
          await post(`/v1/learning/characters/${characterId}/attempts`, {
            requestId: randomUUID(),
            level: "primary1",
            points: 99,
          })
        ).statusCode,
      ).toBe(400);
      expect(
        (
          await post(`/v1/learning/characters/${characterId}/messages`, {
            characters: 1000,
          })
        ).statusCode,
      ).toBe(404);
      const state = await get(`/v1/learning/characters/${characterId}`);
      expect(state.headers["cache-control"]).toBe("no-store");
      expect(state.json<Character>()).toMatchObject({
        roleKey: "oliver",
        level: "primary3",
        characters: 0,
      });
      expect(
        (await get(`/v1/learning/characters/${characterId}/history?cursor=invalid`))
          .statusCode,
      ).toBe(400);
      const oldTables =
        await database.sql`select to_regclass('app.learning_states') as old_state,to_regclass('app.unit_learning_attempts') as old_attempts`;
      expect(oldTables[0]).toEqual({ old_state: null, old_attempts: null });
    });

    it("开启、判题、请求重放、版本冲突、补答与账号导出走真实服务", async () => {
      await fill();
      const requestId = randomUUID();
      const started = await post(`/v1/learning/characters/${characterId}/attempts`, {
        requestId,
      });
      expect(started.statusCode).toBe(200);
      const attempt = started.json<{ attempt: Attempt }>().attempt;
      expect(attempt.level).toBe("primary3");
      expect(started.body).not.toContain('"acceptedAnswers"');
      expect(started.body).not.toContain('"explanation"');
      expect((await get(`/v1/learning/attempts/${attempt.id}`, 1)).statusCode).toBe(
        404,
      );
      const input = {
        requestId: randomUUID(),
        roundId: attempt.round.id,
        expectedRevision: attempt.revision,
        questionId: "q.choice",
        answer: { kind: "choice", optionId: "hello" },
      };
      const answered = await post(`/v1/learning/attempts/${attempt.id}/answers`, input);
      expect(answered.statusCode).toBe(200);
      const answer = answered.json<Awaited<ReturnType<LearningService["answer"]>>>();
      expect(answer.awardedPoints).toBe(1);
      expect(
        (await post(`/v1/learning/attempts/${attempt.id}/answers`, input)).json(),
      ).toEqual(answer);
      const stale = await post(`/v1/learning/attempts/${attempt.id}/answers`, {
        ...input,
        requestId: randomUUID(),
      });
      expect(stale.statusCode).toBe(409);
      expect(stale.json<{ code: string }>().code).toBe("LEARNING_REVISION_CONFLICT");
      const finished = await post(`/v1/learning/attempts/${attempt.id}/finish`, {
        requestId: randomUUID(),
        expectedRevision: answer.attempt.revision,
        skipRemaining: true,
      });
      expect(finished.statusCode).toBe(200);
      const closed = finished.json<Attempt>();
      const retry = await post(`/v1/learning/attempts/${attempt.id}/retries`, {
        requestId: randomUUID(),
        expectedRevision: closed.revision,
      });
      expect(retry.statusCode).toBe(200);
      expect(retry.json<Attempt>().round.questionIds).toHaveLength(5);
      expect(
        (await get(`/v1/learning/characters/${characterId}`)).json<Character>()
          .characters,
      ).toBe(0);
      const journey = (await get("/v1/learning/journey")).json<
        Awaited<ReturnType<LearningService["journey"]>>
      >();
      expect(journey.levels.find((p) => p.level === "primary3")?.points).toBe(1);
      expect(
        journey.levels.find((p) => p.level === "primary3")?.publishedUnitCount,
      ).toBe(3);
      expect(
        journey.levels.find((p) => p.level === "senior3")?.publishedUnitCount,
      ).toBe(0);
      const exported = await createAccountService(config(), database).exportData(
        owner(),
      );
      expect(exported.learningRecords).toEqual(
        expect.arrayContaining([expect.objectContaining({ recordType: "reward" })]),
      );
    });

    it("历史稳定翻页不带私有答案，耗尽返回 202 并保留满条", async () => {
      for (let i = 0; i < 2; i++) {
        await fill();
        const result = await post(`/v1/learning/characters/${characterId}/attempts`, {
          requestId: randomUUID(),
        });
        const attempt = result.json<{ attempt: Attempt }>().attempt;
        expect(result.statusCode).toBe(200);
        const finished = await post(`/v1/learning/attempts/${attempt.id}/finish`, {
          requestId: randomUUID(),
          expectedRevision: attempt.revision,
          skipRemaining: true,
        });
        expect(finished.statusCode).toBe(200);
      }
      const seen: string[] = [];
      const points: number[] = [];
      let cursor: string | null = null;
      do {
        const response = await get(
          `/v1/learning/characters/${characterId}/history?limit=1${cursor ? `&cursor=${cursor}` : ""}`,
        );
        expect(response.statusCode).toBe(200);
        expect(response.body).not.toContain('"solution"');
        const page = response.json<Awaited<ReturnType<LearningService["history"]>>>();
        seen.push(...page.items.map((item) => item.id));
        points.push(...page.items.map((item) => item.earnedPoints));
        cursor = page.nextCursor;
      } while (cursor !== null);
      expect(new Set(seen).size).toBe(3);
      expect(seen).toHaveLength(3);
      expect(points.sort()).toEqual([0, 0, 1]);
      await fill();
      const pending = await post(`/v1/learning/characters/${characterId}/attempts`, {
        requestId: randomUUID(),
      });
      expect(pending.statusCode).toBe(202);
      expect(pending.json()).toEqual({ status: "preparing", attempt: null });
      expect(
        (await get(`/v1/learning/characters/${characterId}`)).json<Character>()
          .characters,
      ).toBe(500);
    });

    it("开发者填满只改自己的当前循环，不伪造学习成绩或聊天记录", async () => {
      const target = randomUUID();
      expect(
        (
          await post("/v1/content/commands", {
            commands: [
              {
                commandId: randomUUID(),
                expectedVersion: 0,
                operation: "upsert",
                parentId: null,
                resourceId: target,
                resourceType: "character",
                payload: {
                  schemaVersion: 1,
                  isMainCharacter: true,
                  isFriend: true,
                  difficulty: "primary3",
                  metAt: new Date().toISOString(),
                  card: {
                    name: "Oliver Bennett",
                    age: 24,
                    appearance: "调试验证",
                    gender: "male",
                    hobbies: ["阅读"],
                    nationality: "英国",
                    occupation: "书店店员",
                    personality: "温和",
                    regionId: "london",
                  },
                },
              },
            ],
          })
        ).statusCode,
      ).toBe(200);
      const url = `/v1/dev/learning/characters/${target}/fill`;
      const state = (await get(`/v1/learning/characters/${target}`)).json<Character>();
      // Foundation 的 UUID 编码为大写，必须与数据库的小写 UUID 视为同一循环。
      const command = { requestId: randomUUID(), cycleId: state.cycleId.toUpperCase() };
      const before = (await get("/v1/learning/journey")).json<unknown>();
      expect(
        (await app.inject({ method: "POST", url, payload: command })).statusCode,
      ).toBe(401);
      expect((await post(url, command, 1)).statusCode).toBe(404);
      expect(
        (
          await post(url, {
            ...command,
            requestId: randomUUID(),
            cycleId: randomUUID(),
          })
        ).statusCode,
      ).toBe(409);
      const filled = await post(url, command);
      expect(filled.statusCode).toBe(200);
      expect(filled.json<Character>().characters).toBe(500);
      expect((await post(url, command)).json()).toEqual(filled.json());
      expect(
        (await post(url, { ...command, cycleId: state.cycleId.toLowerCase() })).json(),
      ).toEqual(filled.json());
      expect((await post(url, { ...command, requestId: randomUUID() })).json()).toEqual(
        filled.json(),
      );
      expect((await get("/v1/learning/journey")).json()).toEqual(before);
      const [messages] =
        await database.sql`select count(*)::int as count from app.learning_message_events where user_id=${owner()} and character_id=${target}`;
      expect(messages?.count).toBe(0);
    });

    it("备考方向接口鉴权、严格校验、版本与账号隔离", async () => {
      const url = "/v1/learning/directions";
      expect((await app.inject({ url })).statusCode).toBe(401);
      expect((await app.inject({ method: "POST", url, payload: {} })).statusCode).toBe(
        401,
      );
      const before = (await get(url)).json<unknown>();
      const profileBefore = (await createDomainService(database).getSnapshot(owner()))
        .profile;
      const input = {
        requestId: randomUUID(),
        direction: "toefl-ibt-2026",
        expectedRevision: 0,
      };
      for (const invalid of [
        { ...input, direction: "postgraduate" },
        { ...input, direction: "toefl-essentials" },
        { ...input, expectedRevision: -1 },
        { ...input, expectedRevision: 0.5 },
        { ...input, userId: accounts[1]?.userId },
      ])
        expect((await post(url, invalid)).statusCode).toBe(400);
      expect((await get(url)).json()).toEqual(before);
      const selected = await post(url, input);
      expect(selected.statusCode).toBe(200);
      expect(selected.headers["cache-control"]).toBe("no-store");
      expect(selected.json()).toMatchObject({
        selectedDirection: "toefl-ibt-2026",
        revision: 1,
      });
      expect((await post(url, input)).json()).toEqual(selected.json());
      expect(
        (
          await post(url, {
            ...input,
            requestId: randomUUID(),
            direction: "ielts-academic",
          })
        ).statusCode,
      ).toBe(409);
      expect((await get(url, 1)).json()).toMatchObject({
        selectedDirection: "general",
        revision: 0,
      });
      expect(
        (await createDomainService(database).getSnapshot(owner())).profile,
      ).toEqual(profileBefore);
      expect(
        (
          await post(url, {
            requestId: randomUUID(),
            direction: "general",
            expectedRevision: 1,
          })
        ).statusCode,
      ).toBe(200);
    });

    it("主线只由前章推进，学习星星和自选年级不影响主线，重放与账号隔离仍生效", async () => {
      const domain = createDomainService(database);
      await domain.completeOnboarding(owner(), randomUUID(), {
        starterRegionId: "london",
      });
      const url = "/v1/progression/mainline";
      expect((await app.inject({ url })).statusCode).toBe(401);
      const status = async () => (await get(url)).json<MainlineProgress>();
      const initial = await status();
      expect(initial).not.toHaveProperty("earnedStars");
      expect(initial.chapters[0]?.state).toBe("available");
      expect((await get(url)).headers["cache-control"]).toBe("no-store");
      const current = (await domain.getSnapshot(owner())).profile;
      expect(
        (
          await app.inject({
            method: "PATCH",
            url: "/v1/me",
            headers: { ...headers(), "idempotency-key": randomUUID() },
            payload: { difficulty: "senior3", expectedVersion: current.version },
          })
        ).statusCode,
      ).toBe(200);
      expect(await status()).toEqual(initial);
      const complete = (storyId: string, key = randomUUID()) =>
        app.inject({
          method: "POST",
          url: `/v1/progression/stories/${storyId}/complete`,
          headers: { ...headers(), "idempotency-key": key },
        });
      const blockedKey = randomUUID();
      const blocked = await complete("mainline_capetown", blockedKey);
      expect(blocked.statusCode).toBe(409);
      expect(blocked.json<{ code: string }>().code).toBe("MAINLINE_LOCKED");
      // 仅在隔离测试库设置里程碑，模拟不同年级累积；正式服务只由答题事务写入。
      for (const [level, stars] of [
        ["primary3", 2],
        ["primary4", 1],
      ] as const) {
        for (let star = 1; star <= stars; star++)
          await database.sql`insert into app.learning_milestones(user_id,level_key,star) values(${owner()},${level},${star})`;
      }
      expect(await status()).toEqual(initial);
      expect((await status()).chapters[1]?.lockReason).toBe("previousChapter");
      expect((await complete("mainline_capetown")).statusCode).toBe(409);
      expect((await complete("mainline_london")).statusCode).toBe(200);
      expect((await status()).chapters[1]?.state).toBe("available");
      const finished = await complete("mainline_capetown", blockedKey);
      expect(finished.statusCode).toBe(200);
      expect((await complete("mainline_capetown", blockedKey)).json()).toEqual(
        finished.json(),
      );
      expect((await complete("mainline_capetown")).statusCode).toBe(409);
      expect((await status()).chapters[2]).toMatchObject({
        state: "available",
        lockReason: null,
      });
      expect((await get(url, 1)).json<MainlineProgress>().chapters[1]?.state).toBe(
        "locked",
      );
      // 旧的合法剧情领取凭据在新政策下仍可回看，且不再发奖。
      await database.sql`insert into app.story_reward_claims(user_id,story_id,reward_coins) values(${owner()},'mainline_singapore',120)`;
      expect((await status()).chapters[4]?.state).toBe("completed");
      expect((await complete("mainline_singapore")).statusCode).toBe(409);
    });
    it("原创完整组鉴权、旧端保护、多答案与错答不中断贯通HTTP", async () => {
      const domain = createDomainService(database);
      const currentProfile = (await domain.getSnapshot(owner())).profile;
      await domain.updateProfile(owner(), randomUUID(), {
        difficulty: "primary3",
        expectedVersion: currentProfile.version,
      });
      const fixture = learningFixture(`original.http-${randomUUID()}`);
      const unit = {
        ...fixture,
        roleKey: "companion",
        beats: [],
        originalGroup: {
          id: "http-test",
          family: "passage_form",
          label: "测试语篇填空",
          candidateSHA256: "a".repeat(64),
          authorCheckSHA256: "b".repeat(64),
          sourceGroupIds: ["test.source"],
          sourceNotice: "隔离测试，不发布为教学内容。",
          material:
            "This is a complete ten-response test material, including its final sentence.",
        },
        questions: Array.from({ length: 10 }, (_, i) => ({
          id: `q${String(i)}`,
          goalId: "test.greetings",
          instruction: "填写各空",
          prompt: `第${String(i + 1)}空`,
          explanation: "仅供程序测试的明确解析。",
          hint: "查看完整材料",
          difficultyReason: "程序测试",
          type: "completion",
          acceptedAnswers: ["learned", "learnt"],
          normalization: { ignoreCase: true, ignoreTerminalPunctuation: false },
          marking: {
            protocol: "english_phrase_v1",
            rejectedAnswers: ["learn"],
            maxWords: 1,
            unlisted: "review",
          },
        })),
      };
      unitIds.push(unit.id);
      await repository.publish(unit);
      const indexURL = "/v1/learning/originals?level=primary3";
      expect((await app.inject({ url: indexURL })).statusCode).toBe(401);
      expect(
        (await get(indexURL))
          .json<{ units: { id: string }[] }>()
          .units.some((u) => u.id === unit.id),
      ).toBe(true);
      const previous = (
        await get(`/v1/learning/characters/${characterId}`)
      ).json<Character>();
      if (previous.activeAttemptId) {
        const a = (
          await get(`/v1/learning/attempts/${previous.activeAttemptId}`)
        ).json<Attempt>();
        await post(`/v1/learning/attempts/${a.id}/finish`, {
          requestId: randomUUID(),
          expectedRevision: a.revision,
          skipRemaining: true,
        });
      }
      await fill();
      const input = { requestId: randomUUID(), originalUnitId: unit.id };
      expect(
        (await post(`/v1/learning/characters/${characterId}/attempts`, input))
          .statusCode,
      ).toBe(426);
      const modern = { ...headers(), "x-learning-complete-groups": "1" };
      const started = await app.inject({
        method: "POST",
        url: `/v1/learning/characters/${characterId}/attempts`,
        headers: modern,
        payload: { ...input, requestId: randomUUID() },
      });
      expect(started.statusCode).toBe(200);
      const a = started.json<{ attempt: Attempt }>().attempt;
      expect(a.unit.questions).toHaveLength(10);
      expect(
        a.unit.questions.every((q) => q.material === unit.originalGroup.material),
      ).toBe(true);
      expect(JSON.stringify(a.unit)).not.toContain("acceptedAnswers");
      expect((await get(`/v1/learning/attempts/${a.id}`)).statusCode).toBe(426);
      expect((await get(`/v1/learning/attempts/${a.id}`, 1)).statusCode).toBe(404);
      const command = {
        requestId: randomUUID(),
        expectedRevision: a.revision,
        roundId: a.round.id,
        questionId: "q0",
        answer: { kind: "text", text: "unknownform" },
      };
      const url = `/v1/learning/attempts/${a.id}/answers`;
      const unknown = await app.inject({
        method: "POST",
        url,
        headers: modern,
        payload: command,
      });
      expect(unknown.statusCode).toBe(200);
      expect(unknown.json()).toMatchObject({
        result: { outcome: "incorrect", solution: { kind: "text", text: "learned" } },
        awardedPoints: 0,
      });
      expect(
        (
          await app.inject({ method: "POST", url, headers: modern, payload: command })
        ).json(),
      ).toEqual(unknown.json());
      const fresh = (
        await app.inject({ url: `/v1/learning/attempts/${a.id}`, headers: modern })
      ).json<Attempt>();
      expect(fresh.revision).toBe(a.revision + 1);
      expect(fresh.round.answers).toHaveLength(1);
      const correct = {
        ...command,
        requestId: randomUUID(),
        expectedRevision: fresh.revision,
        questionId: "q1",
        answer: { kind: "text", text: " LEARNT " },
      };
      const receipt = await app.inject({
        method: "POST",
        url,
        headers: modern,
        payload: correct,
      });
      expect(receipt.statusCode).toBe(200);
      expect(receipt.json<{ awardedPoints: number }>().awardedPoints).toBe(1);
      expect(
        (
          await app.inject({ method: "POST", url, headers: modern, payload: correct })
        ).json(),
      ).toEqual(receipt.json());
    });
  },
);
