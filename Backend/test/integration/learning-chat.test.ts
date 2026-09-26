import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import {
  createDomainLearningContext,
  createDomainService,
} from "../../src/modules/domain/service.js";
import {
  createContentReadService,
  createContentService,
} from "../../src/modules/content/service.js";
import { createContentCursorCodec } from "../../src/modules/content/cursor.js";
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import { registerContentRoutes } from "../../src/modules/content/routes.js";
import { learningRoleKey } from "../../src/modules/learning/context.js";
import { createLearningChatService } from "../../src/modules/learning/chat-service.js";
import { createLearningService } from "../../src/modules/learning/service.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { countChatCharacters } from "../../src/modules/learning/policy.js";
import { createAiService } from "../../src/modules/ai/service.js";
import { registerAiRoutes } from "../../src/modules/ai/routes.js";
import { createBillingService } from "../../src/modules/billing/service.js";
import type {
  AiProviderClient,
  AiProviderStreamEvent,
} from "../../src/modules/ai/types.js";
import type { RedisResource } from "../../src/infrastructure/redis/client.js";
import type { LearningMessageOrigin } from "../../src/modules/learning/chat-contract.js";
import { AppError } from "../../src/shared/errors.js";
import { integrationConfig } from "../helpers/integration.js";
import { learningFixture } from "../helpers/learning.js";

// 真实数据库、鉴权、HTTP 和 AI 服务。只替换外部模型和 Redis 计数，不调用付费供应商。
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "可信聊天计数与事务发件箱",
  () => {
    let db: DatabaseResource;
    let app: Awaited<ReturnType<typeof buildApp>>;
    let auth: Awaited<ReturnType<typeof createAuthService>>;
    let chat: ReturnType<typeof createLearningChatService>;
    let learning: ReturnType<typeof createLearningService>;
    let ai: ReturnType<typeof createAiService>;
    let observerFailure = false;
    let providerCalls = 0;
    let generatedBody = "Hello, friend!";
    let partialStream = false;
    const users: string[] = [];
    const units: string[] = [];
    const config = () => integrationConfig({ DEEPSEEK_API_KEY: "test-key" });
    const redis: RedisResource = {
      close: () => Promise.resolve(),
      connect: () => Promise.resolve(),
      consumeFixedWindow: () => Promise.resolve(1),
      onError: () => undefined,
      ping: () => Promise.resolve(),
      putOneTime: () => Promise.resolve(),
      takeOneTime: () => Promise.resolve(null),
    };
    beforeAll(async () => {
      db = createDatabase(config());
      await runMigrations(db);
      auth = await createAuthService(config(), db);
      const content = createContentReadService(db),
        profile = createDomainLearningContext(db);
      const context = {
        profile: profile.difficulty,
        character: async (...args: Parameters<typeof content.character>) =>
          learningRoleKey(await content.character(...args)),
      };
      chat = createLearningChatService(db, context, content);
      learning = createLearningService(db, context, chat.drain);
      const provider: AiProviderClient = {
        configured: true,
        complete: async (request) => {
          providerCalls++;
          await request.onAttempt?.();
          return {
            content: generatedBody,
            model: request.route.model,
            providerRequestId: "test-completion",
            usage: { inputTokens: 10, outputTokens: 10, totalTokens: 20 },
          };
        },
        stream: (request) =>
          Promise.resolve(
            (async function* (): AsyncGenerator<AiProviderStreamEvent> {
              providerCalls++;
              await request.onAttempt?.();
              yield { type: "delta", text: generatedBody };
              if (!partialStream) {
                yield {
                  type: "usage",
                  usage: { inputTokens: 10, outputTokens: 10, totalTokens: 20 },
                };
                yield { type: "done" };
              }
            })(),
          ),
      };
      ai = createAiService(config(), db, redis, createBillingService(db), provider, {
        openRouter: provider,
        chatObserver: {
          begin: chat.begin,
          complete: async (...args) => {
            if (observerFailure) {
              observerFailure = false;
              throw new Error("模拟完成收据暂时写入失败");
            }
            await chat.complete(...args);
          },
        },
      });
      app = await buildApp(config(), { logger: false });
      registerAiRoutes(app, auth, ai);
      registerContentRoutes(
        app,
        auth,
        createContentService(
          db,
          createContentCursorCodec(config().authTokenHashPepper),
          createSyncCursorCodec(config().authTokenHashPepper),
          chat.enqueue,
        ),
      );
    });
    afterAll(async () => {
      await app.close();
      for (const user of users) await db.sql`delete from app.users where id=${user}`;
      for (const unit of units) {
        await db.sql`delete from app.learning_unit_versions where unit_id=${unit}`;
        await db.sql`delete from app.learning_units where id=${unit}`;
      }
      await db.close();
    });
    async function setup() {
      const user = randomUUID(),
        character = randomUUID(),
        conversation = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      await createDomainService(db).getSnapshot(user);
      const tokens = await auth.loginFederated(
        user,
        0,
        { deviceId: "chat-learning-test", platform: "ios" },
        {},
      );
      const headers = { authorization: `Bearer ${tokens.accessToken}` };
      async function put(
        resourceType: string,
        resourceId: string,
        parentId: string | null,
        payload: unknown,
        expectedVersion = 0,
        commandId = randomUUID(),
      ) {
        const response = await app.inject({
          method: "POST",
          url: "/v1/content/commands",
          headers,
          payload: {
            commands: [
              {
                commandId,
                expectedVersion,
                operation: "upsert",
                resourceType,
                resourceId,
                parentId,
                payload,
              },
            ],
          },
        });
        expect(response.statusCode, response.body).toBe(200);
        expect(
          response.json<{ results: { status: string }[] }>().results[0]?.status,
        ).toBe("applied");
        return response;
      }
      const now = new Date().toISOString();
      await put("character", character, null, {
        schemaVersion: 1,
        isMainCharacter: true,
        isFriend: true,
        difficulty: "junior1",
        metAt: now,
        card: {
          name: "Oliver Bennett",
          age: 28,
          appearance: "测试",
          gender: "male",
          hobbies: ["books"],
          nationality: "British",
          occupation: "Bookseller",
          personality: "测试",
          regionId: "london",
        },
      });
      await put("conversation", conversation, character, {
        schemaVersion: 1,
        createdAt: now,
        lastMessageAt: now,
        isArchived: false,
        isEncounterSession: false,
        lastSummarizedMessageIndex: 0,
        turnCount: 0,
      });
      const state = await learning.character(user, character);
      const userOrigin: LearningMessageOrigin = {
        source: "user",
        cycleId: state.cycleId,
      };
      function payload(
        text: string,
        role = "user",
        origin?: LearningMessageOrigin,
        interrupted = false,
      ) {
        return {
          schemaVersion: 1,
          createdAt: now,
          isInterrupted: interrupted,
          kind: "text",
          orderIndex: 0,
          role,
          text,
          tokenEstimate: 10,
          ...(origin ? { learningOrigin: origin } : {}),
        };
      }
      async function message(
        text: string,
        role = "user",
        origin?: LearningMessageOrigin,
        interrupted = false,
      ) {
        const id = randomUUID();
        await put(
          "message",
          id,
          conversation,
          payload(text, role, origin, interrupted),
        );
        return id;
      }
      async function count() {
        return (await learning.character(user, character)).characters;
      }
      function input(userMessageId: string, text: string, operationId = randomUUID()) {
        return {
          operationId,
          task: "conversation",
          responseFormat: "text" as const,
          messages: [{ role: "user" as const, content: text }],
          learningChat: {
            conversationId: conversation,
            userMessageId,
            cycleId: state.cycleId,
          },
        };
      }
      function assistant(
        operationId: string,
        userMessageId: string,
        index = 0,
        total = 1,
      ): LearningMessageOrigin {
        return {
          source: "assistant",
          cycleId: state.cycleId,
          userMessageId,
          operationId,
          fragmentIndex: index,
          fragmentCount: total,
        };
      }
      return {
        user,
        character,
        conversation,
        headers,
        put,
        payload,
        message,
        count,
        state,
        userOrigin,
        input,
        assistant,
      };
    }

    it("只计新用户正文；Unicode、重传、编辑、历史导入和保存回滚", async () => {
      const s = await setup(),
        text = "你 好 e\u0301 👨‍👩‍👧‍👦 🇨🇳";
      const id = randomUUID(),
        command = randomUUID();
      await s.put(
        "message",
        id,
        s.conversation,
        s.payload(text, "user", s.userOrigin, true),
        0,
        command,
      );
      await s.put(
        "message",
        id,
        s.conversation,
        s.payload(text, "user", s.userOrigin, true),
        0,
        command,
      );
      await Promise.all([chat.drain(s.user), chat.drain(s.user)]);
      expect(await s.count()).toBe(countChatCharacters(text));
      await s.put(
        "message",
        id,
        s.conversation,
        s.payload("edited " + text, "user", s.userOrigin),
        1,
      );
      await s.message("历史导入".repeat(100));
      await s.message("主动问候", "assistant");
      expect(await s.count()).toBe(countChatCharacters(text));
      const service = createContentService(
        db,
        createContentCursorCodec(config().authTokenHashPepper),
        createSyncCursorCodec(config().authTokenHashPepper),
        async (...args) => {
          await chat.enqueue(...args);
          throw new AppError({
            code: "TEST_ROLLBACK",
            message: "测试回滚",
            statusCode: 409,
          });
        },
      );
      const rejected = randomUUID();
      const result = await service.executeCommands(s.user, [
        {
          commandId: randomUUID(),
          expectedVersion: 0,
          operation: "upsert",
          resourceType: "message",
          resourceId: rejected,
          parentId: s.conversation,
          payload: s.payload("不应保存", "user", s.userOrigin),
        },
      ]);
      expect(result[0]?.status).toBe("rejected");
      expect(
        await db.sql`select 1 from app.learning_chat_outbox where user_id=${s.user} and message_id=${rejected}`,
      ).toHaveLength(0);
      expect(
        await db.sql`select 1 from app.content_records where user_id=${s.user} and resource_id=${rejected}`,
      ).toHaveLength(0);
    });

    it("完整模型回复与全部保存气泡核对；同轮重生成和重放不重复计数", async () => {
      const s = await setup(),
        text = "Hello";
      const userMessage = await s.message(text, "user", s.userOrigin);
      generatedBody = "Hello, friend!";
      const input = s.input(userMessage, text);
      const calls = providerCalls;
      const response = await app.inject({
        method: "POST",
        url: "/v1/ai/completions",
        headers: s.headers,
        payload: input,
      });
      expect(response.statusCode, response.body).toBe(200);
      expect(await s.count()).toBe(5);
      await s.message(
        "Hello, ",
        "assistant",
        s.assistant(input.operationId, userMessage, 0, 2),
      );
      expect(await s.count()).toBe(5);
      await s.message(
        "friend!",
        "assistant",
        s.assistant(input.operationId, userMessage, 1, 2),
      );
      await Promise.all([chat.drain(s.user), chat.drain(s.user)]);
      expect(await s.count()).toBe(5 + countChatCharacters(generatedBody));
      await ai.complete(s.user, input);
      expect(providerCalls).toBe(calls + 1);
      generatedBody = "Another complete response.";
      const regenerated = s.input(userMessage, text);
      await ai.complete(s.user, regenerated);
      await s.message(
        generatedBody,
        "assistant",
        s.assistant(regenerated.operationId, userMessage),
      );
      expect(await s.count()).toBe(5 + countChatCharacters("Hello, friend!"));
      const rows = await db.sql<
        { body: string | null }[]
      >`select body from app.learning_chat_outbox where user_id=${s.user}`;
      expect(rows.every((row) => row.body === null)).toBe(true);
    });

    it("拒绝伪造正文、跨账号、旧消息补签、非聊天任务与不完整流", async () => {
      const s = await setup(),
        other = await setup(),
        text = "Hello";
      const id = await s.message(text, "user", s.userOrigin);
      const input = s.input(id, text);
      generatedBody = "Verified response";
      await ai.complete(s.user, input);
      await s.message(
        "Fabricated response",
        "assistant",
        s.assistant(input.operationId, id),
      );
      expect(await s.count()).toBe(5);
      await other.message(
        generatedBody,
        "assistant",
        s.assistant(input.operationId, id),
      );
      expect(await other.count()).toBe(0);
      await expect(ai.complete(s.user, s.input(id, "Altered"))).rejects.toMatchObject({
        code: "LEARNING_CHAT_CONTEXT_INVALID",
      });
      await expect(ai.complete(other.user, input)).rejects.toMatchObject({
        code: "LEARNING_CHAT_CONTEXT_INVALID",
      });
      await expect(
        ai.complete(s.user, { ...s.input(id, text), task: "translation" }),
      ).rejects.toMatchObject({ code: "LEARNING_CHAT_CONTEXT_INVALID" });
      const old = await s.message("Imported");
      await s.put(
        "message",
        old,
        s.conversation,
        s.payload("Imported", "user", s.userOrigin),
        1,
      );
      await expect(ai.complete(s.user, s.input(old, "Imported"))).rejects.toMatchObject(
        { code: "LEARNING_CHAT_CONTEXT_INVALID" },
      );
      partialStream = true;
      const partial = s.input(id, text);
      const stream = await ai.stream(s.user, partial);
      await expect(
        (async () => {
          for await (const event of stream.events) void event;
        })(),
      ).rejects.toMatchObject({ code: "AI_UPSTREAM_PROTOCOL_ERROR" });
      partialStream = false;
      await s.message(generatedBody, "assistant", s.assistant(partial.operationId, id));
      expect(await s.count()).toBe(5);
    });

    it("结束首轮后的迟到消息不会填新周期，历史补答不改变周期", async () => {
      const s = await setup(),
        text = "a".repeat(1000);
      const id = await s.message(text, "user", s.userOrigin);
      const input = s.input(id, text);
      generatedBody = "Late response";
      await ai.complete(s.user, input);
      expect(await s.count()).toBe(1000);
      const repository = new LearningEngineRepository(db);
      const unit = {
        ...learningFixture(`test.chat-${randomUUID()}`),
        level: "junior1" as const,
      };
      units.push(unit.id);
      await repository.publish(unit);
      const started = await learning.start(s.user, randomUUID(), s.character);
      if (!started.attempt) throw new Error("测试挑战未分配");
      await learning.finish(s.user, randomUUID(), {
        attemptId: started.attempt.id,
        expectedRevision: started.attempt.revision,
        skipRemaining: true,
      });
      await s.message(generatedBody, "assistant", s.assistant(input.operationId, id));
      await s.message("Old offline text", "user", s.userOrigin);
      expect(await s.count()).toBe(0);
      const state = await learning.character(s.user, s.character);
      await s.message("Fresh", "user", { source: "user", cycleId: state.cycleId });
      expect(await s.count()).toBe(5);
    });

    it("模型完成收据故障可从服务端缓存重放修复，不再次调用供应商", async () => {
      const s = await setup(),
        id = await s.message("Hi", "user", s.userOrigin),
        input = s.input(id, "Hi");
      generatedBody = "Hello again";
      const calls = providerCalls;
      observerFailure = true;
      const stream = await ai.stream(s.user, input);
      await expect(
        (async () => {
          for await (const event of stream.events) void event;
        })(),
      ).rejects.toThrow("模拟完成收据");
      const replay = await ai.stream(s.user, input);
      for await (const event of replay.events) void event;
      expect(providerCalls).toBe(calls + 1);
      await s.message(generatedBody, "assistant", s.assistant(input.operationId, id));
      expect(await s.count()).toBe(2 + countChatCharacters(generatedBody));
    });
  },
);
