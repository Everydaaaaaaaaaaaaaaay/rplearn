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
import { learningFixture } from "../helpers/learning.js";

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
        const unit = learningFixture(`test.api-${randomUUID()}`);
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
      let cursor: string | null = null;
      do {
        const response = await get(
          `/v1/learning/characters/${characterId}/history?limit=1${cursor ? `&cursor=${cursor}` : ""}`,
        );
        expect(response.statusCode).toBe(200);
        expect(response.body).not.toContain('"solution"');
        const page = response.json<Awaited<ReturnType<LearningService["history"]>>>();
        seen.push(...page.items.map((item) => item.id));
        cursor = page.nextCursor;
      } while (cursor !== null);
      expect(new Set(seen).size).toBe(3);
      expect(seen).toHaveLength(3);
      await fill();
      const pending = await post(`/v1/learning/characters/${characterId}/attempts`, {
        requestId: randomUUID(),
      });
      expect(pending.statusCode).toBe(202);
      expect(pending.json()).toEqual({ status: "preparing", attempt: null });
      expect(
        (await get(`/v1/learning/characters/${characterId}`)).json<Character>()
          .characters,
      ).toBe(1000);
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
      expect(filled.json<Character>().characters).toBe(1000);
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
  },
);
