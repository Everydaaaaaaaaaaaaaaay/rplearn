import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { createDomainService } from "../../src/modules/domain/service.js";
import {
  createContentService,
  createChatContentService,
} from "../../src/modules/content/service.js";
import { createContentCursorCodec } from "../../src/modules/content/cursor.js";
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import { registerContentRoutes } from "../../src/modules/content/routes.js";
import { createChatService } from "../../src/modules/chat/service.js";
import { registerChatRoutes } from "../../src/modules/chat/routes.js";
import type {
  ChatState,
  ChatGenerationInput,
} from "../../src/modules/chat/contracts.js";
import { integrationConfig } from "../helpers/integration.js";

// Real HTTP, authentication, PostgreSQL and concurrent device sessions. The external
// model is controllable so tests can stop exactly between admission and completion.
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "shared chat across devices",
  () => {
    let db: DatabaseResource;
    let app: Awaited<ReturnType<typeof buildApp>>;
    let auth: Awaited<ReturnType<typeof createAuthService>>;
    let chat: ReturnType<typeof createChatService>;
    let baseURL: string;
    const users: string[] = [];
    const calls: ChatGenerationInput[] = [];
    const completed = new Map<string, string>();
    let release: (() => void) | undefined;
    let block = false;
    beforeAll(async () => {
      const config = integrationConfig();
      db = createDatabase(config);
      await runMigrations(db);
      auth = await createAuthService(config, db);
      chat = createChatService(db, createChatContentService(db), {
        generate: async (input, onDelta) => {
          calls.push(input);
          await onDelta("A shared reply.");
          if (block)
            await new Promise<void>((resolve) => {
              release = resolve;
            });
          completed.set(input.generationId, "A shared reply.");
          return "A shared reply.";
        },
        recover: (input) => {
          const content = completed.get(input.generationId);
          return Promise.resolve(content === undefined ? null : { content });
        },
        coalesceMilliseconds: 0,
        leaseMilliseconds: 1_000,
      });
      app = await buildApp(config, { logger: false });
      registerChatRoutes(app, auth, chat);
      registerContentRoutes(
        app,
        auth,
        createContentService(
          db,
          createContentCursorCodec(config.authTokenHashPepper),
          createSyncCursorCodec(config.authTokenHashPepper),
          chat.observe,
          chat.beforeCommand,
        ),
      );
      baseURL = await app.listen({ host: "127.0.0.1", port: 0 });
    });
    afterAll(async () => {
      release?.();
      await app.close();
      for (const user of users) await db.sql`delete from app.users where id=${user}`;
      await db.close();
    });
    async function setup(encounter = false) {
      const user = randomUUID(),
        character = randomUUID(),
        conversation = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      await createDomainService(db).getSnapshot(user);
      const a = await auth.loginFederated(
        user,
        0,
        { deviceId: "device-a", platform: "ios" },
        {},
      );
      const b = await auth.loginFederated(
        user,
        0,
        { deviceId: "device-b", platform: "ios" },
        {},
      );
      const request = async (token: string, path: string, body?: unknown) =>
        fetch(baseURL + path, {
          method: body === undefined ? "GET" : "POST",
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
      const put = async (
        token: string,
        type: string,
        id: string,
        parentId: string | null,
        payload: unknown,
        commandId: string = randomUUID(),
        expectedVersion = 0,
      ) => {
        const response = await request(token, "/v1/content/commands", {
          commands: [
            {
              commandId,
              expectedVersion,
              operation: "upsert",
              resourceType: type,
              resourceId: id,
              parentId,
              payload,
            },
          ],
        });
        expect(response.status).toBe(200);
        const result = (await response.json()) as {
          results: { status: string; record?: unknown; error?: unknown }[];
        };
        expect(result.results[0]?.status, JSON.stringify(result)).toBe("applied");
        return result.results[0]?.record;
      };
      const now = new Date().toISOString();
      await put(a.accessToken, "character", character, null, {
        schemaVersion: 1,
        isMainCharacter: true,
        isFriend: !encounter,
        difficulty: "junior1",
        metAt: now,
        card: {
          name: "Shared Friend",
          age: 28,
          appearance: "Test",
          gender: "female",
          hobbies: ["books"],
          nationality: "British",
          occupation: "Guide",
          personality: "Warm",
          regionId: "london",
        },
      });
      await put(a.accessToken, "conversation", conversation, character, {
        schemaVersion: 1,
        createdAt: now,
        lastMessageAt: now,
        isArchived: false,
        isEncounterSession: encounter,
        lastSummarizedMessageIndex: 0,
        turnCount: 0,
      });
      const opened = await request(
        a.accessToken,
        `/v1/chat/characters/${character}/open`,
        { protocolVersion: 1 },
      );
      expect(opened.status).toBe(200);
      const initial = (await opened.json()) as ChatState;
      const message = (text: string, createdAt = now) => ({
        schemaVersion: 1,
        createdAt,
        isInterrupted: true,
        kind: "text",
        orderIndex: 1,
        role: "user",
        text,
        tokenEstimate: 3,
      });
      const send = (
        token: string,
        id: string,
        text: string,
        commandId?: string,
        createdAt?: string,
      ) =>
        put(
          token,
          "message",
          id,
          initial.conversationId,
          message(text, createdAt),
          commandId,
        );
      const state = async (token = a.accessToken) => {
        const response = await request(
          token,
          `/v1/chat/conversations/${initial.conversationId}`,
        );
        expect(response.status).toBe(200);
        return (await response.json()) as ChatState;
      };
      return {
        user,
        character,
        conversation: initial.conversationId,
        a,
        b,
        request,
        send,
        state,
        put,
        message,
      };
    }
    it("both devices resolve the same canonical conversation", async () => {
      const f = await setup();
      const response = await f.request(
        f.b.accessToken,
        `/v1/chat/characters/${f.character}/open`,
        { protocolVersion: 1 },
      );
      expect(((await response.json()) as ChatState).conversationId).toBe(
        f.conversation,
      );
    });
    it("keeps both concurrent messages and replays a lost acknowledgement without duplicating a turn", async () => {
      const f = await setup();
      const a = randomUUID(),
        b = randomUUID(),
        command = randomUUID();
      await Promise.all([
        f.send(f.a.accessToken, a, "From A", command),
        f.send(f.b.accessToken, b, "From B"),
      ]);
      await f.send(f.a.accessToken, a, "From A", command);
      const state = await f.state();
      expect(state.records.filter((r) => r.resourceType === "message")).toHaveLength(2);
      expect(
        new Set(
          state.records
            .filter((r) => r.resourceType === "message")
            .map((r) => (r.payload as { orderIndex: number }).orderIndex),
        ).size,
      ).toBe(2);
      const before = calls.length;
      await Promise.all([chat.processNext(), chat.processNext()]);
      expect(calls.length - before).toBe(1);
      const done = await f.state(f.b.accessToken);
      expect(done.coveredMessageIds.sort()).toEqual([a, b].sort());
      expect(
        done.records.filter(
          (r) => (r.payload as { role?: string }).role === "assistant",
        ),
      ).toHaveLength(1);
    });
    it("orders a delayed earlier client timestamp after an already accepted B message", async () => {
      const f = await setup();
      const a = randomUUID(),
        b = randomUUID();
      await f.send(
        f.b.accessToken,
        b,
        "B arrives first",
        undefined,
        "2026-11-05T10:00:02Z",
      );
      await f.send(
        f.a.accessToken,
        a,
        "A was typed first",
        undefined,
        "2026-11-05T10:00:01Z",
      );
      const messages = (await f.state()).records.filter(
        (r) => r.resourceType === "message",
      );
      expect(messages.map((m) => m.resourceId)).toEqual([b, a]);
      await chat.processNext();
    });
    it("queues input accepted during inference and builds its next context from committed replies", async () => {
      const f = await setup();
      const first = randomUUID(),
        later = randomUUID();
      await f.send(f.a.accessToken, first, "First question");
      block = true;
      const running = chat.processNext();
      for (let attempt = 0; attempt < 100 && release === undefined; attempt++)
        await new Promise((resolve) => setTimeout(resolve, 5));
      expect(release).toBeDefined();
      await f.send(f.b.accessToken, later, "A question during generation");
      const observed = await f.state(f.b.accessToken);
      expect(observed.generation?.partialText).toBe("A shared reply.");
      expect(await chat.processNext()).toBe(false);
      block = false;
      release?.();
      release = undefined;
      await running;
      await chat.processNext();
      const next = calls.at(-1);
      if (!next) throw new Error("Expected a generation call");
      expect(next.inputMessageIds).toEqual([later]);
      expect(
        next.messages.some(
          (m) => m.role === "assistant" && m.content === "A shared reply.",
        ),
      ).toBe(true);
      expect((await f.state()).coveredMessageIds.sort()).toEqual([first, later].sort());
    });
    it("a replaced producer cannot publish a late response or trigger an automatic second model call", async () => {
      const f = await setup();
      const id = randomUUID();
      await f.send(f.a.accessToken, id, "Recover this input");
      block = true;
      const running = chat.processNext();
      for (let attempt = 0; attempt < 100 && release === undefined; attempt++)
        await new Promise((resolve) => setTimeout(resolve, 5));
      const before = calls.length;
      await db.sql`update app.chat_generations set lease_until=now()-interval '1 second'
      where user_id=${f.user} and status='dispatched'`;
      expect(await chat.processNext()).toBe(true);
      block = false;
      release?.();
      release = undefined;
      await running;
      expect(calls.length).toBe(before);
      expect(
        (await f.state()).records.filter(
          (r) => (r.payload as { role?: string }).role === "assistant",
        ),
      ).toHaveLength(0);
      const commandId = randomUUID();
      await f.request(
        f.a.accessToken,
        `/v1/chat/conversations/${f.conversation}/retry`,
        { commandId },
      );
      await f.request(
        f.b.accessToken,
        `/v1/chat/conversations/${f.conversation}/retry`,
        { commandId },
      );
      await chat.processNext();
      expect(calls.length).toBe(before);
      expect((await f.state()).coveredMessageIds).toEqual([id]);
      expect(
        (await f.state()).records.filter(
          (r) => (r.payload as { role?: string }).role === "assistant",
        ),
      ).toHaveLength(1);
    });
    it("an old offline conversation alias accepts its message into the canonical history", async () => {
      const f = await setup();
      const alias = randomUUID(),
        id = randomUUID(),
        now = new Date().toISOString();
      await f.put(f.b.accessToken, "conversation", alias, f.character, {
        schemaVersion: 1,
        createdAt: now,
        lastMessageAt: now,
        isArchived: false,
        isEncounterSession: false,
        lastSummarizedMessageIndex: 0,
        turnCount: 0,
      });
      await f.put(
        f.b.accessToken,
        "message",
        id,
        alias,
        f.message("From the offline alias"),
      );
      const state = await f.state();
      expect(state.records.find((record) => record.resourceId === id)?.parentId).toBe(
        f.conversation,
      );
      expect(
        (
          state.records.find((record) => record.resourceId === alias)?.payload as {
            isArchived: boolean;
          }
        ).isArchived,
      ).toBe(true);
      await chat.processNext();
    });
    it("defers a same-device successor that arrives before its predecessor and accepts the same retry ID", async () => {
      const f = await setup();
      const first = randomUUID(),
        second = randomUUID(),
        commandId = randomUUID();
      const command = {
        commandId,
        expectedVersion: 0,
        operation: "upsert",
        resourceType: "message",
        resourceId: second,
        parentId: f.conversation,
        payload: {
          ...f.message("Second on the same device"),
          sharedPredecessorId: first,
        },
      };
      const deferred = await f.request(f.a.accessToken, "/v1/content/commands", {
        commands: [command],
      });
      expect(
        ((await deferred.json()) as { results: { error: { code: string } }[] })
          .results[0]?.error.code,
      ).toBe("CHAT_PREDECESSOR_PENDING");
      await f.send(f.a.accessToken, first, "First on the same device");
      const retried = await f.request(f.a.accessToken, "/v1/content/commands", {
        commands: [command],
      });
      expect(
        ((await retried.json()) as { results: { status: string }[] }).results[0]
          ?.status,
      ).toBe("applied");
      expect(
        (await f.state()).records
          .filter((r) => r.resourceType === "message")
          .map((r) => r.resourceId),
      ).toEqual([first, second]);
      await chat.processNext();
    });
    it("protects accepted body and server ordering against stale metadata updates", async () => {
      const f = await setup(),
        id = randomUUID();
      const accepted = (await f.send(
        f.a.accessToken,
        id,
        "Keep the accepted text",
      )) as { version: number };
      await f.put(
        f.b.accessToken,
        "message",
        id,
        f.conversation,
        { ...f.message("Overwrite from an old device"), orderIndex: 900 },
        undefined,
        accepted.version,
      );
      const message = (await f.state()).records.find((r) => r.resourceId === id);
      if (!message) throw new Error("Missing accepted message");
      expect((message.payload as { text: string; orderIndex: number }).text).toBe(
        "Keep the accepted text",
      );
      expect((message.payload as { orderIndex: number }).orderIndex).toBe(1);
      await chat.processNext();
    });
    it("requires an explicit idempotent retry when dispatch outcome cannot be recovered", async () => {
      const f = await setup(),
        id = randomUUID();
      await f.send(f.a.accessToken, id, "An uncertain interrupted turn");
      block = true;
      const running = chat.processNext();
      for (let attempt = 0; attempt < 100 && release === undefined; attempt++)
        await new Promise((resolve) => setTimeout(resolve, 5));
      const initial = await f.state();
      const generation = initial.generation;
      if (!generation) throw new Error("Expected a dispatched generation");
      await db.sql`update app.chat_generations set lease_until=now()-interval '1 second' where id=${generation.id}`;
      await chat.processNext();
      block = false;
      release?.();
      release = undefined;
      await running;
      completed.delete(generation.id);
      const before = calls.length;
      expect((await f.state()).generation?.status).toBe("uncertain");
      expect(await chat.processNext()).toBe(false);
      expect(calls.length).toBe(before);
      const commandId = randomUUID();
      await Promise.all([
        f.request(f.a.accessToken, `/v1/chat/conversations/${f.conversation}/retry`, {
          commandId,
        }),
        f.request(f.b.accessToken, `/v1/chat/conversations/${f.conversation}/retry`, {
          commandId,
        }),
      ]);
      await chat.processNext();
      expect(calls.length).toBe(before + 1);
      expect((await f.state()).coveredMessageIds).toEqual([id]);
    });
    it("stale conversation preferences cannot erase server-completed turn counts", async () => {
      const f = await setup();
      await f.send(f.a.accessToken, randomUUID(), "Complete one turn");
      await chat.processNext();
      const record = (await f.state()).records.find(
        (r) => r.resourceId === f.conversation,
      );
      if (!record) throw new Error("Missing canonical conversation");
      await f.put(
        f.b.accessToken,
        "conversation",
        f.conversation,
        f.character,
        {
          ...(record.payload as Record<string, unknown>),
          turnCount: 0,
          isPinned: true,
        },
        undefined,
        record.version,
      );
      expect(
        (
          (await f.state()).records.find((r) => r.resourceId === f.conversation)
            ?.payload as { turnCount: number }
        ).turnCount,
      ).toBe(1);
    });
    it("retiring an encounter cancels its producer and preserves archived input", async () => {
      const f = await setup(true),
        input = randomUUID();
      await f.send(f.a.accessToken, input, "An encounter question");
      const record = (await f.state()).records.find(
        (r) => r.resourceId === f.conversation,
      );
      if (!record) throw new Error("Missing encounter conversation");
      await f.put(
        f.a.accessToken,
        "conversation",
        f.conversation,
        f.character,
        { ...(record.payload as Record<string, unknown>), isArchived: true },
        undefined,
        record.version,
      );
      expect(
        (await f.request(f.a.accessToken, `/v1/chat/conversations/${f.conversation}`))
          .status,
      ).toBe(404);
      expect(await chat.processNext()).toBe(false);
      const archived =
        await db.sql`select 1 from app.content_records where user_id=${f.user} and resource_id=${input} and deleted_at is null`;
      expect(archived).toHaveLength(1);
    });
    it("a second account cannot read or retry another account's conversation", async () => {
      const owner = await setup(),
        stranger = await setup();
      expect(
        (
          await stranger.request(
            stranger.a.accessToken,
            `/v1/chat/conversations/${owner.conversation}`,
          )
        ).status,
      ).toBe(404);
      expect(
        (
          await stranger.request(
            stranger.a.accessToken,
            `/v1/chat/conversations/${owner.conversation}/retry`,
            { commandId: randomUUID() },
          )
        ).status,
      ).toBe(404);
    });
  },
);
