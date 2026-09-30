import { createHash } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import type { AuthService } from "../../src/modules/auth/service.js";
import { createContentCursorCodec } from "../../src/modules/content/cursor.js";
import { registerContentRoutes } from "../../src/modules/content/routes.js";
import { createContentService } from "../../src/modules/content/service.js";
import type {
  ContentCommandResult,
  ContentPage,
} from "../../src/modules/content/types.js";
import { createDomainService } from "../../src/modules/domain/service.js";
import { createLearningMilestoneReader } from "../../src/modules/learning/service.js";
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import { registerSyncRoutes } from "../../src/modules/sync/routes.js";
import { createSyncService } from "../../src/modules/sync/service.js";
import type { SyncPage } from "../../src/modules/sync/types.js";
import { newEntityId } from "../../src/shared/id.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "旧版普通聊天同步兼容",
  () => {
    let app: FastifyInstance;
    let database: DatabaseResource;
    const userId = newEntityId();
    const now = "2026-10-01T00:00:00.000Z";
    const characterId = newEntityId();
    // 属性次序对应旧版入口 Schema，旧回执哈希必须仍然匹配。
    const conversation = {
      commandId: newEntityId(),
      expectedVersion: 0,
      operation: "upsert",
      parentId: characterId,
      payload: {
        createdAt: now,
        isArchived: false,
        isEncounterSession: false,
        lastMessageAt: now,
        lastSummarizedMessageIndex: 0,
        quizOptOut: false,
        schemaVersion: 2,
        turnCount: 0,
        turnsSinceQuiz: 4,
      },
      resourceId: newEntityId(),
      resourceType: "conversation",
    } as const;
    const headers = { authorization: "Bearer isolated-test" };
    const post = (commands: readonly unknown[]) =>
      app.inject({
        method: "POST",
        url: "/v1/content/commands",
        headers,
        payload: { commands },
      });
    const compatibility = { quizOptOut: true, turnsSinceQuiz: 0 };

    beforeAll(async () => {
      const config = integrationConfig();
      database = createDatabase(config);
      await runMigrations(database);
      await database.sql`insert into app.users (id) values (${userId})`;
      const auth = {
        authenticate: (token: string) =>
          token === "isolated-test"
            ? Promise.resolve({
                userId,
                sessionId: newEntityId(),
                tokenVersion: 0,
              })
            : Promise.reject(new Error("测试令牌无效")),
      } as AuthService;
      app = await buildApp(config, { logger: false });
      const cursor = createSyncCursorCodec(config.authTokenHashPepper);
      registerContentRoutes(
        app,
        auth,
        createContentService(
          database,
          createContentCursorCodec(config.authTokenHashPepper),
          cursor,
        ),
      );
      registerSyncRoutes(
        app,
        auth,
        createSyncService(
          database,
          createDomainService(database, createLearningMilestoneReader()),
          cursor,
        ),
      );
      const parent = await post([
        {
          commandId: newEntityId(),
          expectedVersion: 0,
          operation: "upsert",
          parentId: null,
          payload: {
            card: {
              age: 28,
              appearance: "短发",
              gender: "female",
              hobbies: ["阅读"],
              name: "测试旅伴",
              nationality: "测试",
              occupation: "向导",
              personality: "友好",
              regionId: "london",
            },
            difficulty: "junior1",
            isFriend: true,
            isMainCharacter: true,
            metAt: now,
            schemaVersion: 2,
          },
          resourceId: characterId,
          resourceType: "character",
        },
      ]);
      expect(
        parent.json<{ results: ContentCommandResult[] }>().results[0]?.status,
      ).toBe("applied");
    });

    afterAll(async () => {
      await app.close();
      await database.sql`delete from app.users where id = ${userId}`;
      await database.close();
    });

    it("兼容旧端完整同步和幂等重放，废弃字段不进入持久化记录", async () => {
      const upload = await post([conversation]);
      expect(upload.statusCode).toBe(200);
      expect(upload.json()).toMatchObject({
        results: [
          { status: "applied", record: { version: 1, payload: compatibility } },
        ],
      });
      expect((await post([conversation])).json()).toEqual(upload.json());
      const [stored] = await database.sql<
        { payload: Record<string, unknown>; version: number }[]
      >`select payload, version from app.content_records where user_id = ${userId} and resource_id = ${conversation.resourceId}`;
      expect(stored?.version).toBe(1);
      expect(stored?.payload).not.toHaveProperty("quizOptOut");
      expect(stored?.payload).not.toHaveProperty("turnsSinceQuiz");
      const [receipt] = await database.sql<
        { request_hash: string; response: unknown }[]
      >`select request_hash, response from app.command_receipts where user_id = ${userId} and command_id = ${conversation.commandId}`;
      expect(receipt?.request_hash).toBe(
        createHash("sha256").update(JSON.stringify(conversation)).digest("hex"),
      );
      expect(receipt?.response).not.toHaveProperty("payload.quizOptOut");
      const page = await app.inject({
        method: "GET",
        url: "/v1/content/records",
        headers,
      });
      expect(
        page
          .json<ContentPage>()
          .records.find((r) => r.resourceId === conversation.resourceId)?.payload,
      ).toMatchObject(compatibility);
      const changes = await app.inject({
        method: "GET",
        url: "/v1/sync/changes",
        headers,
      });
      const change = changes
        .json<SyncPage>()
        .changes.find(
          (entry) =>
            (entry.payload as { resourceId?: string }).resourceId ===
            conversation.resourceId,
        );
      expect(change?.payload).toMatchObject({
        resourceId: conversation.resourceId,
        payload: compatibility,
      });
      const conflict = await post([{ ...conversation, commandId: newEntityId() }]);
      expect(conflict.json()).toMatchObject({
        results: [
          {
            status: "rejected",
            error: {
              code: "CONTENT_VERSION_CONFLICT",
              details: { current: { payload: compatibility } },
            },
          },
        ],
      });
      const currentPayload: Record<string, unknown> = { ...conversation.payload };
      delete currentPayload.quizOptOut;
      delete currentPayload.turnsSinceQuiz;
      const current = await post([
        {
          ...conversation,
          commandId: newEntityId(),
          expectedVersion: 1,
          payload: currentPayload,
        },
      ]);
      expect(current.json()).toMatchObject({
        results: [{ status: "applied", record: { version: 2 } }],
      });
      const changedRequest = await post([
        { ...conversation, payload: { ...conversation.payload, turnCount: 10 } },
      ]);
      expect(changedRequest.json()).toMatchObject({
        results: [{ status: "rejected", error: { code: "IDEMPOTENCY_KEY_CONFLICT" } }],
      });
      const message = {
        commandId: newEntityId(),
        expectedVersion: 0,
        operation: "upsert",
        parentId: conversation.resourceId,
        payload: {
          createdAt: now,
          isInterrupted: false,
          kind: "text",
          orderIndex: 0,
          quizChosenIndex: 1,
          quizJson: "旧字段",
          role: "user",
          schemaVersion: 1,
          text: "保留普通消息",
          tokenEstimate: 1,
        },
        resourceId: newEntityId(),
        resourceType: "message",
      };
      expect((await post([message])).json()).toMatchObject({
        results: [{ status: "applied", record: { payload: { text: "保留普通消息" } } }],
      });
      const [savedMessage] = await database.sql<
        { payload: Record<string, unknown> }[]
      >`select payload from app.content_records where user_id = ${userId} and resource_id = ${message.resourceId}`;
      expect(savedMessage?.payload).not.toHaveProperty("quizJson");
      expect(savedMessage?.payload).not.toHaveProperty("quizChosenIndex");
      expect(
        (
          await post([
            {
              ...message,
              commandId: newEntityId(),
              payload: { ...message.payload, kind: "quiz" },
            },
          ])
        ).statusCode,
      ).toBe(400);
    });
  },
);
