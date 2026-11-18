import { spawn, type ChildProcess } from "node:child_process";
import { randomUUID } from "node:crypto";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";
import type { ChatState } from "../../src/modules/chat/contracts.js";
const listen = (s: Server): Promise<number> =>
  new Promise((done, reject) => {
    s.once("error", reject);
    s.listen(0, "127.0.0.1", () => {
      s.off("error", reject);
      done((s.address() as AddressInfo).port);
    });
  });
const warmTurnLimit = 25_000; // Newly met characters still wait for the real typing schedule.
const voiceReply = "I can hear the station announcements from here.";
const textReplies = [
  "The rain should clear by noon.",
  "Fancy a walk beside the canal?",
  "That bakery makes excellent buns.",
  "We could catch the earlier train.",
  "I left my umbrella at home.",
  "The market shuts at five today.",
];

describe.runIf(process.env.RUN_E2E_TESTS === "true")(
  "compiled shared-chat API and worker",
  () => {
    let db: DatabaseResource | undefined,
      api: ChildProcess,
      worker: ChildProcess,
      provider: Server | undefined;
    let env: NodeJS.ProcessEnv,
      url: string,
      user: string,
      a: string,
      b: string,
      character: string,
      conversation: string;
    let blocked = false,
      providerCalls = 0,
      output = "";
    let cycleId = "";
    let release: (() => void) | undefined;
    const prompts: { role: string; content: string }[][] = [];
    function start(file: string) {
      const child = spawn(process.execPath, [resolve("dist", file)], {
        env,
        stdio: ["ignore", "pipe", "pipe"],
      });
      const capture = (v: Buffer) => {
        output = (output + v.toString()).slice(-30_000);
      };
      child.stdout.on("data", capture);
      child.stderr.on("data", capture);
      return child;
    }
    async function stop(child?: ChildProcess, force = false) {
      if (child?.exitCode !== null || child.signalCode !== null) return;
      const stopped = new Promise<void>((done) => child.once("exit", () => done()));
      child.kill(force ? "SIGKILL" : "SIGTERM");
      await Promise.race([
        stopped,
        delay(10_000).then(() => {
          throw new Error("Test child failed to stop");
        }),
      ]);
    }
    async function until<T>(
      read: () => Promise<T>,
      accept: (v: T) => boolean,
    ): Promise<T> {
      const deadline = Date.now() + warmTurnLimit;
      while (Date.now() < deadline) {
        const v = await read();
        if (accept(v)) return v;
        await delay(50);
      }
      throw new Error(`Shared chat timeout\n${output}`);
    }
    async function request(token: string, path: string, body?: unknown) {
      try {
        return await fetch(url + path, {
          method: body === undefined ? "GET" : "POST",
          signal: AbortSignal.timeout(30_000),
          headers: {
            authorization: `Bearer ${token}`,
            "content-type": "application/json",
          },
          ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
      } catch (cause) {
        throw new Error(`Shared chat request failed: ${path}\n${output}`, { cause });
      }
    }
    async function state(token = a, input?: string) {
      const response = await request(
        token,
        `/v1/chat/conversations/${conversation}${input ? `?inputMessageId=${input}` : ""}`,
      );
      expect(response.status).toBe(200);
      return (await response.json()) as ChatState;
    }
    async function put(
      token: string,
      type: string,
      id: string,
      parentId: string | null,
      payload: unknown,
      commandId = randomUUID(),
    ) {
      const response = await request(token, "/v1/content/commands", {
        commands: [
          {
            commandId,
            resourceType: type,
            resourceId: id,
            parentId,
            operation: "upsert",
            expectedVersion: 0,
            payload,
          },
        ],
      });
      expect(response.status).toBe(200);
      const result = (await response.json()) as { results: { status: string }[] };
      expect(result.results[0]?.status, JSON.stringify(result)).toBe("applied");
    }
    function send(
      token: string,
      id: string,
      text: string,
      commandId = randomUUID(),
      timestamp = new Date().toISOString(),
    ) {
      return put(
        token,
        "message",
        id,
        conversation,
        {
          schemaVersion: 1,
          role: "user",
          kind: "text",
          text,
          createdAt: timestamp,
          orderIndex: 1,
          isInterrupted: true,
          tokenEstimate: 4,
          learningOrigin: { source: "user", cycleId },
        },
        commandId,
      );
    }
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      provider = createServer((req, res) => {
        void (async () => {
          if (req.url === "/models") {
            res.setHeader("content-type", "application/json");
            res.end(JSON.stringify({ data: [{ id: "deepseek-v4-flash" }] }));
            return;
          }
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(Buffer.from(chunk as Uint8Array));
          const request = JSON.parse(Buffer.concat(chunks).toString()) as {
            messages: { role: string; content: string }[];
            stream?: boolean;
          };
          prompts.push(request.messages);
          providerCalls++;
          const id = `fixture-${providerCalls.toString()}`;
          const model = "deepseek-v4-flash";
          const text = request.stream
            ? voiceReply
            : textReplies[(providerCalls - 1) % textReplies.length];
          if (!text) throw new Error("Missing completion fixture");
          const usage = {
            prompt_tokens: 40,
            completion_tokens: 10,
            total_tokens: 50,
            prompt_cache_hit_tokens: 0,
            prompt_cache_miss_tokens: 40,
          };
          if (request.stream) {
            res.setHeader("content-type", "text/event-stream");
            res.write(
              `data: ${JSON.stringify({ id, model, choices: [{ delta: { content: text } }] })}\n\n`,
            );
          }
          if (blocked)
            await new Promise<void>((done) => {
              release = done;
            });
          if (request.stream) {
            res.write(`data: ${JSON.stringify({ id, model, choices: [], usage })}\n\n`);
            res.end("data: [DONE]\n\n");
          } else {
            res.setHeader("content-type", "application/json");
            res.end(
              JSON.stringify({
                id,
                model,
                choices: [{ message: { content: text } }],
                usage,
              }),
            );
          }
        })().catch(() => res.destroy());
      });
      const providerPort = await listen(provider),
        reserved = createServer(),
        port = await listen(reserved);
      await new Promise<void>((done) => reserved.close(() => done()));
      url = `http://127.0.0.1:${port.toString()}`;
      env = {
        ...process.env,
        NODE_ENV: "development",
        HOST: "127.0.0.1",
        PORT: String(port),
        LOG_LEVEL: "warn",
        DEEPSEEK_API_KEY: "local-fixture",
        DEEPSEEK_BASE_URL: `http://127.0.0.1:${providerPort.toString()}`,
        OPENROUTER_API_KEY: "",
        APPLE_AUTH_ENABLED: "false",
        APPLE_BILLING_ENABLED: "false",
        ADMIN_API_ENABLED: "false",
        MEDIA_STORAGE_ENABLED: "false",
        LEARNING_GENERATION_ENABLED: "false",
        OTEL_TRACING_ENABLED: "false",
        SMTP_USER: "",
        SMTP_PASSWORD: "",
        JOB_POLL_INTERVAL_MS: "100",
      };
      api = start("server.js");
      const readyBy = Date.now() + 30_000;
      let readiness = "The socket has not opened yet.";
      while (Date.now() < readyBy) {
        if (api.exitCode !== null || api.signalCode !== null) {
          throw new Error(`The shared-chat API exited during startup\n${output}`);
        }
        try {
          const response = await fetch(url + "/health/ready", {
            signal: AbortSignal.timeout(2_000),
          });
          if (response.ok) {
            readiness = "";
            break;
          }
          readiness = `HTTP ${String(response.status)}: ${await response.text()}`;
        } catch (error) {
          readiness = String(error);
        }
        await delay(100);
      }
      if (readiness) {
        throw new Error(
          `The shared-chat API did not become ready: ${readiness}\n${output}`,
        );
      }
      const email = `shared-e2e-${randomUUID()}@example.com`,
        password = "Local-E2e-Password-42!";
      expect((await request("", "/v1/auth/register", { email, password })).status).toBe(
        202,
      );
      const [row] = await db.sql<
        { user_id: string }[]
      >`update app.user_identities set email_verified_at=now() where provider='email' and provider_subject=${email} returning user_id`;
      if (!row) throw new Error("Missing registered user");
      user = row.user_id;
      const login = async (deviceId: string) => {
        const response = await request("", "/v1/auth/login", {
          email,
          password,
          device: { deviceId, platform: "ios" },
        });
        expect(response.status).toBe(200);
        return ((await response.json()) as { accessToken: string }).accessToken;
      };
      a = await login("actual-device-a");
      b = await login("actual-device-b");
      expect((await request(a, "/v1/me")).status).toBe(200);
      character = randomUUID();
      conversation = randomUUID();
      const now = new Date().toISOString();
      await put(a, "character", character, null, {
        schemaVersion: 1,
        isMainCharacter: true,
        isFriend: true,
        difficulty: "junior1",
        metAt: new Date(Date.now() - 5_000).toISOString(),
        card: {
          name: "E2E Friend",
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
      await put(a, "conversation", conversation, character, {
        schemaVersion: 1,
        createdAt: now,
        lastMessageAt: now,
        isArchived: false,
        isEncounterSession: false,
        lastSummarizedMessageIndex: 0,
        turnCount: 0,
      });
      const opened = await request(a, `/v1/chat/characters/${character}/open`, {
        protocolVersion: 1,
      });
      expect(opened.status).toBe(200);
      conversation = ((await opened.json()) as ChatState).conversationId;
      const learning = await request(a, `/v1/learning/characters/${character}`);
      expect(learning.status).toBe(200);
      cycleId = ((await learning.json()) as { cycleId: string }).cycleId;
      worker = start("worker.js");
    }, 60_000);
    afterEach(() => {
      blocked = false;
      release?.();
      release = undefined;
    });
    afterAll(async () => {
      await stop(worker).catch(() => undefined);
      await stop(api).catch(() => undefined);
      if (provider) {
        provider.closeAllConnections();
        const configuredProvider = provider;
        await new Promise<void>((done) => configuredProvider.close(() => done()));
      }
      if (db && user) {
        await db.sql`delete from app.jobs where user_id=${user}`;
        await db.sql`delete from app.audit_events where actor_user_id=${user}`;
        await db.sql`delete from app.users where id=${user}`;
      }
      await db?.close();
    }, 30_000);
    it(
      "coalesces devices, preserves lost-ack IDs and uses arrival order",
      async () => {
        if (!db) throw new Error("Missing test database");
        const first = randomUUID(),
          delayed = randomUUID(),
          command = randomUUID();
        const now = Date.now();
        const firstAt = new Date(now).toISOString();
        const earlierAt = new Date(now - 1_000).toISOString();
        await send(b, first, "B arrived first", command, firstAt);
        await send(a, delayed, "A was sent earlier", undefined, earlierAt);
        await send(b, first, "B arrived first", command, firstAt);
        const done = await until(
          () => state(b),
          (s) => s.coveredMessageIds.includes(delayed),
        );
        expect(
          done.records
            .filter((r) => r.resourceType === "message")
            .map((r) => r.resourceId)
            .slice(0, 2),
        ).toEqual([first, delayed]);
        expect(providerCalls).toBe(1);
        expect((await state(a)).records).toEqual((await state(b)).records);
        expect(
          await db.sql`select 1 from app.credit_operations where user_id=${user} and task='conversation' and status='settled'`,
        ).toHaveLength(1);
      },
      warmTurnLimit + 5_000,
    );
    it(
      "queues messages during inference and resolves earlier completed turns by input ID",
      async () => {
        blocked = true;
        const first = randomUUID(),
          later = randomUUID(),
          before = providerCalls;
        await send(a, first, "First live question");
        await until(() => Promise.resolve(release !== undefined), Boolean);
        const during = await state(b);
        expect(during.generation).toMatchObject({
          status: "dispatched",
          inputMessageIds: [first],
        });
        expect(during.coveredMessageIds).not.toContain(first);
        await send(b, later, "A message while the reply is running");
        blocked = false;
        release?.();
        release = undefined;
        await until(
          () => state(b),
          (s) => s.coveredMessageIds.includes(later),
        );
        expect(providerCalls - before).toBe(2);
        const earlier = (await state(a, first)).generation;
        expect(earlier?.status).toBe("completed");
        expect(earlier?.partialText).toBeTruthy();
        expect(prompts.at(-1)).toContainEqual({
          role: "assistant",
          content: earlier?.partialText,
        });
      },
      warmTurnLimit * 2 + 5_000,
    );
    it(
      "recovers a billed result after worker death without a second provider call",
      async () => {
        blocked = true;
        const database = db;
        if (!database) throw new Error("Missing test database");
        const input = randomUUID(),
          before = providerCalls;
        await send(a, input, "Recover after a worker crash");
        await until(() => Promise.resolve(release !== undefined), Boolean);
        const generation = (await state()).generation;
        if (!generation) throw new Error("Missing dispatched generation");
        let locked = false;
        const unlock = Promise.withResolvers<undefined>();
        const held = database.sql.begin(async (sql) => {
          await sql`select pg_advisory_xact_lock(hashtextextended(${`${user}:shared-chat`},0))`;
          locked = true;
          await unlock.promise;
        });

        try {
          await until(() => Promise.resolve(locked), Boolean);
          blocked = false;
          release?.();
          release = undefined;
          await until(
            async () =>
              database.sql`select 1 from app.credit_operations where user_id=${user} and operation_id=${generation.id} and result is not null`,
            (rows) => rows.length === 1,
          );
          await stop(worker, true);
        } finally {
          unlock.resolve(undefined);
          await held;
        }
        await database.sql`update app.chat_generations set lease_until=now()-interval '1 second' where id=${generation.id}`;
        worker = start("worker.js");
        await until(
          () => state(b),
          (s) => s.coveredMessageIds.includes(input),
        );
        expect(providerCalls - before).toBe(1);
        expect(
          await database.sql`select 1 from app.credit_operations where user_id=${user} and operation_id=${generation.id}`,
        ).toHaveLength(1);
        expect(
          await database.sql`select 1 from app.chat_messages where user_id=${user} and answered_by=${generation.id}`,
        ).toHaveLength(1);
      },
      warmTurnLimit * 3 + 5_000,
    );
    it(
      "reuses the shared reply in a valid voice lease and preserves server learning receipts",
      async () => {
        if (!db) throw new Error("Missing test database");
        const lease = randomUUID(),
          input = randomUUID(),
          text = "A voice question";
        const authorization = await request(a, "/v1/access/voice", {
          operationId: lease,
        });
        expect(authorization.status).toBe(200);
        const before = providerCalls;
        await put(a, "message", input, conversation, {
          schemaVersion: 1,
          role: "user",
          kind: "text",
          text,
          createdAt: new Date().toISOString(),
          orderIndex: 1,
          isInterrupted: true,
          tokenEstimate: 4,
          sharedVoiceLeaseId: lease,
          voiceReceiptVersion: 1,
          learningOrigin: { source: "user", cycleId },
        });
        const done = await until(
          () => state(b, input),
          (s) => s.generation?.status === "completed",
        );
        expect(done.generation?.partialText).toBe(voiceReply);
        expect(done.coveredMessageIds).not.toContain(input);
        expect(
          (
            await request(a, `/v1/chat/conversations/${conversation}/voice-receipt`, {
              messageId: input,
              text: voiceReply,
              interrupted: false,
            })
          ).status,
        ).toBe(200);
        const heard = await state(b, input);
        expect(heard.coveredMessageIds).toContain(input);
        expect(
          heard.records.find(
            (record) =>
              record.resourceType === "message" &&
              (record.payload as { text?: string }).text === voiceReply,
          ),
        ).toMatchObject({
          payload: { role: "assistant", text: voiceReply },
        });
        expect(providerCalls - before).toBe(1);
        expect(prompts.at(-1)?.[0]?.content).toContain("real-time voice call");
        const receipt =
          await db.sql`select 1 from app.learning_chat_operations where user_id=${user} and operation_id=${done.generation?.id ?? null} and body_fingerprint is not null`;
        expect(receipt).toHaveLength(1);
        expect(
          (await request(a, "/v1/access/voice/stop", { operationId: lease })).status,
        ).toBe(200);
      },
      warmTurnLimit + 5_000,
    );
    it(
      "a closed call lease cannot prevent later text conversation",
      async () => {
        const lease = randomUUID(),
          voiceInput = randomUUID(),
          textInput = randomUUID(),
          before = providerCalls;
        expect(
          (await request(a, "/v1/access/voice", { operationId: lease })).status,
        ).toBe(200);
        expect(
          (await request(a, "/v1/access/voice/stop", { operationId: lease })).status,
        ).toBe(200);
        await put(a, "message", voiceInput, conversation, {
          schemaVersion: 1,
          role: "user",
          kind: "text",
          text: "Previous closed call",
          createdAt: new Date().toISOString(),
          orderIndex: 1,
          isInterrupted: true,
          tokenEstimate: 4,
          sharedVoiceLeaseId: lease,
          learningOrigin: { source: "user", cycleId },
        });
        await until(
          () => state(),
          (s) => s.generation?.status === "failed",
        );
        await send(b, textInput, "Continue by text");
        const done = await until(
          () => state(),
          (s) => s.coveredMessageIds.includes(textInput),
        );
        expect(done.coveredMessageIds).toContain(voiceInput);
        expect(providerCalls - before).toBe(1);
      },
      warmTurnLimit * 2 + 5_000,
    );
    it("rejects legacy direct reply producers", async () => {
      const before = providerCalls;
      const response = await request(b, "/v1/ai/completions", {
        task: "conversation",
        operationId: randomUUID(),
        responseFormat: "text",
        messages: [{ role: "user", content: "Legacy duplicate" }],
      });
      expect(response.status).toBe(409);
      expect(((await response.json()) as { code: string }).code).toBe(
        "CHAT_PROTOCOL_REQUIRED",
      );
      expect(providerCalls).toBe(before);
    });
  },
);
