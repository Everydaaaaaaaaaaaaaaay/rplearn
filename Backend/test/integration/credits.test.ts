import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createCreditService } from "../../src/modules/access/credit-service.js";
import { createAccessService } from "../../src/modules/access/service.js";
import { newEntityId } from "../../src/shared/id.js";
import { createAiService } from "../../src/modules/ai/service.js";
import { createDeepSeekClient } from "../../src/modules/ai/deepseek/client.js";
import { createBillingService } from "../../src/modules/billing/service.js";
const req = {
  task: "conversation",
  provider: "deepseek",
  model: "deepseek-v4-flash",
  messages: [{ role: "user" as const, content: "Hello" }],
  maxOutputTokens: 3000,
};
const usage = {
  inputTokens: 5000,
  cacheHitTokens: 4000,
  cacheMissTokens: 1000,
  outputTokens: 500,
  totalTokens: 5500,
};
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "cost credit ledger",
  () => {
    let runtime: RuntimeDependencies;
    let credits: ReturnType<typeof createCreditService>;
    const actors: string[] = [];
    async function actor(guest = false) {
      const id = newEntityId();
      actors.push(id);
      await runtime.database.sql`insert into app.users(id) values(${id})`;
      if (guest)
        await runtime.database
          .sql`insert into app.guest_installations(user_id,installation_hash) values(${id},${id.replaceAll("-", "").repeat(2)})`;
      return id;
    }
    beforeAll(async () => {
      runtime = createRuntimeDependencies(
        loadConfig({ ...process.env, NODE_ENV: "test" }),
      );
      await runMigrations(runtime.database);
      await runtime.start();
      credits = createCreditService(runtime.database);
    });
    afterAll(async () => {
      for (const id of actors)
        await runtime.database.sql`delete from app.users where id=${id}`;
      await runtime.close();
    });
    it.each([false, true])(
      "empty output is a failed, service-funded operation (stream=%s)",
      async (streaming) => {
        const user = await actor();
        const config = loadConfig({
          ...process.env,
          NODE_ENV: "test",
          DEEPSEEK_API_KEY: "test",
        });
        const provider = createDeepSeekClient(config, () =>
          Promise.resolve(
            streaming
              ? new Response(
                  'data: {"id":"empty","model":"deepseek-v4-flash","choices":[{"delta":{"content":""}}]}\n\ndata: {"choices":[],"usage":{"prompt_tokens":100,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":100,"completion_tokens":120,"total_tokens":220}}\n\ndata: [DONE]\n\n',
                )
              : Response.json({
                  id: "empty",
                  model: req.model,
                  choices: [{ message: { content: "" } }],
                  usage: {
                    prompt_tokens: 100,
                    prompt_cache_hit_tokens: 0,
                    prompt_cache_miss_tokens: 100,
                    completion_tokens: 120,
                    total_tokens: 220,
                  },
                }),
          ),
        );
        const ai = createAiService(
          config,
          runtime.database,
          runtime.redis,
          createBillingService(runtime.database),
          provider,
        );
        const operationId = newEntityId();
        const input = {
          task: "conversation",
          operationId,
          messages: req.messages,
          responseFormat: "text" as const,
        };
        await expect(
          (async () => {
            if (!streaming) return ai.complete(user, input);
            const response = await ai.stream(user, input);
            for await (const event of response.events)
              expect(event.type).not.toBe("done");
            return undefined;
          })(),
        ).rejects.toMatchObject({ code: "AI_EMPTY_RESPONSE" });
        expect((await credits.snapshot(user)).remaining).toBe(100);
        const [row] = await runtime.database
          .sql`select billing_scope,status,reason,settled_units::text, result from app.credit_operations where user_id=${user} and operation_id=${operationId}`;
        expect(row).toMatchObject({
          billing_scope: "service",
          status: "settled",
          reason: "AI_EMPTY_RESPONSE",
          result: null,
        });
        expect(Number(row?.settled_units)).toBeGreaterThan(0);
        await expect(ai.complete(user, input)).rejects.toMatchObject({
          code: "OPERATION_FINALIZED",
        });
      },
    );

    it("serializes competing requests and never dispatches a replay", async () => {
      const user = await actor(),
        ids = Array.from({ length: 8 }, () => newEntityId());
      const results = await Promise.allSettled(
        ids.map((id) => credits.reserve(user, id, id, req)),
      );
      const accepted = ids.filter((_, i) => results[i]?.status === "fulfilled");
      expect(accepted.length).toBe(8);
      expect((await credits.snapshot(user)).reserved).toBe(0);
      expect((await credits.snapshot(user)).remaining).toBe(100);
      const id = accepted[0];
      if (!id) throw new Error("No requests accepted");
      await credits.dispatch(user, id);
      await credits.finish(
        user,
        id,
        usage,
        { content: "hello" },
        "provider-1",
        req.model,
      );
      const b = await credits.snapshot(user);
      expect(b.used).toBeGreaterThan(0);
      expect(b.used).toBeLessThan(8);
      expect((await credits.reserve(user, id, id, req)).replay).toBe(true);
      await expect(credits.dispatch(user, id)).rejects.toMatchObject({
        code: "OPERATION_FINALIZED",
      });
      await expect(credits.reserve(user, id, "changed", req)).rejects.toMatchObject({
        code: "OPERATION_CONFLICT",
      });
      await credits.finish(user, id, null);
      expect((await credits.snapshot(user)).used).toBe(b.used);
    });
    it("keeps product automation out of user credits across several explicit operations", async () => {
      const user = await actor();
      const first = newEntityId();
      const conversation = {
        ...req,
        messages: [
          { role: "system" as const, content: "x".repeat(24_000) },
          { role: "user" as const, content: "I must say pretty good" },
        ],
        maxOutputTokens: 120,
      };
      await credits.reserve(user, first, first, conversation);
      await credits.dispatch(user, first);
      await credits.finish(
        user,
        first,
        usage,
        { content: "Glad to hear it." },
        "provider-first",
        req.model,
      );

      const review = newEntityId();
      await credits.reserve(user, review, review, {
        ...req,
        task: "coach_review",
        messages: [{ role: "system", content: "x".repeat(7_081) }],
        maxOutputTokens: 1_000,
      });
      await credits.dispatch(user, review);

      const whileReviewRuns = await credits.snapshot(user);
      expect(whileReviewRuns.used).toBeLessThan(8);
      expect(whileReviewRuns.reserved).toBe(0);
      expect(
        whileReviewRuns.recent.every((entry) => entry.task !== "coach_review"),
      ).toBe(true);

      // Product automation has its own abuse/cost ceiling, independent of the
      // user's 100 credits. Oversized automatic work degrades silently.
      await expect(
        credits.reserve(user, newEntityId(), "second-review", {
          ...req,
          task: "memory_summary",
          messages: [{ role: "user", content: "x".repeat(40_000) }],
          maxOutputTokens: 1_000,
        }),
      ).rejects.toMatchObject({ code: "AUXILIARY_BUDGET_EXHAUSTED" });

      // The review remains dispatched while explicit requests continue. Its
      // hold is absent from the user ledger rather than merely deprioritized.
      const second = newEntityId();
      await expect(
        credits.reserve(user, second, second, conversation),
      ).resolves.toMatchObject({ replay: false });

      await credits.dispatch(user, second);
      await credits.finish(user, second, usage, {}, "provider-second", req.model);

      // Keep the original review in flight through a third user turn as well.
      const third = newEntityId();
      await expect(
        credits.reserve(user, third, third, conversation),
      ).resolves.toMatchObject({ replay: false });
      await credits.dispatch(user, third);

      // Explicit learning tools belong to the user pool, not the helper pool.
      const translation = newEntityId();
      await expect(
        credits.reserve(user, translation, translation, {
          ...req,
          task: "translation",
          maxOutputTokens: 100,
        }),
      ).resolves.toMatchObject({ replay: false });
      await credits.dispatch(user, translation);
      await credits.finish(
        user,
        translation,
        {
          inputTokens: 100,
          cacheHitTokens: 80,
          cacheMissTokens: 20,
          outputTokens: 20,
          totalTokens: 120,
        },
        {},
        "provider-translation",
        req.model,
      );

      await credits.finish(user, third, usage, {}, "provider-third", req.model);
      await credits.finish(user, review, usage, {}, "provider-review", req.model);
      const final = await credits.snapshot(user);
      expect(final.used).toBeLessThan(24);
      expect(
        final.recent.every(
          (entry) => entry.task !== "coach_review" && entry.task !== "memory_summary",
        ),
      ).toBe(true);
    });
    it("classifies every current automatic task as service-funded", async () => {
      const user = await actor();
      const automaticTasks = [
        "coach_review",
        "memory_summary",
        "proactive_message",
        "quiz",
        "speech_feedback",
      ];
      const tinyUsage = {
        inputTokens: 1,
        cacheHitTokens: 0,
        cacheMissTokens: 1,
        outputTokens: 1,
        totalTokens: 2,
      };

      for (const task of automaticTasks) {
        const operation = newEntityId();
        await credits.reserve(user, operation, operation, {
          ...req,
          task,
          maxOutputTokens: 1,
        });
        await credits.dispatch(user, operation);
        await credits.finish(user, operation, tinyUsage, {}, task, req.model);
      }

      const snapshot = await credits.snapshot(user);
      expect(snapshot.used).toBe(0);
      expect(snapshot.remaining).toBe(100);
      expect(snapshot.recent).toEqual([]);
      const scopes = await runtime.database.sql<
        { task: string; billing_scope: string }[]
      >`select task,billing_scope from app.credit_operations where user_id=${user} order by task`;
      expect(scopes).toEqual(
        [...automaticTasks].sort().map((task) => ({ task, billing_scope: "service" })),
      );
      const [route] = await runtime.database.sql<
        { max_output_tokens: number }[]
      >`select max_output_tokens from app.ai_routes where task='proactive_message'`;
      expect(route?.max_output_tokens).toBe(128);
    });
    it("keeps unknown costs auditable without freezing credits across resets", async () => {
      const user = await actor(),
        pending = newEntityId(),
        unused = newEntityId();
      await credits.reserve(user, pending, pending, req);
      await credits.dispatch(user, pending);
      await credits.reserve(user, unused, unused, req);
      await runtime.database
        .sql`update app.credit_operations set expires_at=now()-interval '1 second',window_key='day:2000-01-01' where user_id=${user}`;
      const snapshot = await credits.snapshot(user);
      expect(snapshot.pending).toBe(0);
      expect(snapshot.remaining).toBe(100);
      expect(snapshot.reserved).toBe(0);
      await expect(credits.reserve(user, pending, pending, req)).rejects.toMatchObject({
        code: "OPERATION_FINALIZED",
      });
      await expect(credits.reconcile(user, pending, 0n, "")).rejects.toThrow();
      await credits.reconcile(
        user,
        pending,
        12345n,
        "provider statement request 12345",
      );
      expect((await credits.snapshot(user)).pending).toBe(0);
      await expect(
        credits.reconcile(user, pending, 0n, "cannot charge twice"),
      ).rejects.toThrow();
    });
    it("allows the last credit to finish a full operation, charges actual cost and stops the next", async () => {
      const user = await actor();
      const previous = newEntityId();
      await credits.reserve(user, previous, previous, req);
      await runtime.database
        .sql`update app.credit_operations set status='settled',settled_units=99000000 where user_id=${user} and operation_id=${previous}`;
      expect((await credits.snapshot(user)).remaining).toBe(1);
      const last = newEntityId();
      await credits.reserve(user, last, last, req);
      expect((await credits.snapshot(user)).remaining).toBe(1);
      await credits.dispatch(user, last);
      await credits.finish(
        user,
        last,
        usage,
        { content: "Complete reply" },
        "last-credit",
        req.model,
      );
      const after = await credits.snapshot(user);
      expect(after.used).toBeGreaterThan(100);
      expect(after.remaining).toBe(0);
      expect(after.pending).toBe(0);
      expect(after.reserved).toBe(0);
      await expect(
        credits.reserve(user, newEntityId(), "next", req),
      ).rejects.toMatchObject({ code: "CREDITS_EXHAUSTED" });
      // A paid result can still be replayed with an exhausted balance.
      expect((await credits.reserve(user, last, last, req)).replay).toBe(true);
      // Yesterday's completed overrun cannot freeze today's refreshed allowance.
      await runtime.database
        .sql`update app.credit_operations set window_key='day:2000-01-01' where user_id=${user}`;
      expect((await credits.snapshot(user)).remaining).toBe(100);
    });

    it("restores the screenshot's frozen balance without deleting unresolved accounting records", async () => {
      const user = await actor();
      const paid = newEntityId();
      await credits.reserve(user, paid, paid, req);
      await runtime.database
        .sql`update app.credit_operations set status='settled',settled_units=10249344 where user_id=${user} and operation_id=${paid}`;
      for (const estimate of [42804000, 15318000, 14478000, 14169000]) {
        const id = newEntityId();
        await credits.reserve(user, id, id, req);
        await credits.dispatch(user, id);
        await credits.finish(user, id, null);
        await runtime.database
          .sql`update app.credit_operations set reserved_units=${estimate} where user_id=${user} and operation_id=${id}`;
      }
      const snapshot = await credits.snapshot(user);
      expect(snapshot.remaining).toBe(89.750656);
      expect(snapshot.used).toBe(10.249344);
      expect(snapshot.reserved).toBe(0);
      expect(snapshot.pending).toBe(0);
      expect(snapshot.recent.filter((item) => item.status === "pending")).toHaveLength(
        4,
      );
      expect(snapshot.recent.every((item) => item.heldCredits === 0)).toBe(true);
      const next = newEntityId();
      await expect(
        credits.reserve(user, next, next, { ...req, maxOutputTokens: 16000 }),
      ).resolves.toMatchObject({ replay: false });
    });

    it("preserves guest lifetime spending and increases daily budget on upgrade without resetting spending", async () => {
      const user = await actor(true),
        id = newEntityId();
      await credits.reserve(user, id, id, req);
      await credits.dispatch(user, id);
      await credits.finish(user, id, usage, {}, "p", req.model);
      await runtime.database
        .sql`update app.credit_operations set created_at=now()-interval '40 days' where user_id=${user}`;
      expect((await credits.snapshot(user)).used).toBeGreaterThan(0);
      expect((await credits.snapshot(user)).resetsAt).toBeNull();
      const free = await actor(),
        op = newEntityId();
      await credits.reserve(free, op, op, req);
      await credits.dispatch(free, op);
      await credits.finish(free, op, usage, {}, "p", req.model);
      const before = await credits.snapshot(free);
      await runtime.database
        .sql`insert into app.entitlement_grants(id,user_id,plan_id,entitlement_key,environment,source_provider,source_reference_id,status,provider_event_at)
      values(${newEntityId()},${free},'plus','subscription','test','manual',${newEntityId()},'active',now())`;
      const after = await credits.snapshot(free);
      expect(after.used).toBe(before.used);
      expect(after.limit).toBe(400);
      await runtime.database
        .sql`update app.entitlement_grants set status='expired' where user_id=${free}`;
      expect((await credits.snapshot(free)).used).toBe(before.used);
    });
    it("does not bill local voice seconds and allows only one linked repair", async () => {
      const user = await actor(),
        access = createAccessService(runtime.database),
        before = await credits.snapshot(user),
        voice = newEntityId();
      await access.reserveVoice(user, voice);
      await access.stopVoice(user, voice);
      expect((await credits.snapshot(user)).remaining).toBe(before.remaining);
      const parent = newEntityId();
      await credits.reserve(user, parent, parent, req);
      await credits.dispatch(user, parent);
      await credits.finish(user, parent, usage, { content: "hello" }, "p", req.model);
      const repair = newEntityId();
      await credits.reserve(user, repair, repair, {
        ...req,
        parentOperationId: parent,
      });
      await expect(
        credits.reserve(user, newEntityId(), "repair2", {
          ...req,
          parentOperationId: parent,
        }),
      ).rejects.toMatchObject({ code: "REPAIR_NOT_ALLOWED" });
    });
    it("uses real adapter usage for complete/stream and prevents implicit retries on uncertain errors", async () => {
      const user = await actor();
      let calls = 0;
      let mode = "complete";
      let upstreamSignal: AbortSignal | undefined;
      const config = loadConfig({
        ...process.env,
        NODE_ENV: "test",
        DEEPSEEK_API_KEY: "test",
      });
      const client = createDeepSeekClient(config, async (_url, init) => {
        upstreamSignal = init?.signal ?? undefined;
        await Promise.resolve();
        calls++;
        if (mode === "error") throw new Error("connection lost");
        const raw = {
          prompt_tokens: 5000,
          prompt_cache_hit_tokens: 4000,
          prompt_cache_miss_tokens: 1000,
          completion_tokens: 500,
          total_tokens: 5500,
        };
        if (mode === "stream")
          return new Response(
            "data: " +
              JSON.stringify({
                id: "s",
                model: "deepseek-flash",
                choices: [{ delta: { content: "hello" } }],
              }) +
              "\n\ndata: " +
              JSON.stringify({
                choices: [],
                usage: {
                  prompt_tokens: raw.prompt_tokens,
                  prompt_tokens_details: { cached_tokens: raw.prompt_cache_hit_tokens },
                  completion_tokens: raw.completion_tokens,
                  total_tokens: raw.total_tokens,
                },
              }) +
              "\n\ndata: [DONE]\n\n",
          );
        return Response.json({
          id: "c",
          model: req.model,
          choices: [{ message: { content: "hello" } }],
          usage: raw,
        });
      });
      const ai = createAiService(
        config,
        runtime.database,
        runtime.redis,
        createBillingService(runtime.database),
        client,
      );
      const input = {
        task: "conversation",
        operationId: newEntityId(),
        messages: req.messages,
        responseFormat: "text" as const,
        maxOutputTokens: 500,
      };
      await ai.complete(user, input);
      await ai.complete(user, input);
      expect(calls).toBe(1);
      const before = (await credits.snapshot(user)).used;
      mode = "stream";
      const cancellation = new AbortController();
      const stream = await ai.stream(user, {
        ...input,
        operationId: newEntityId(),
        signal: cancellation.signal,
      });
      for await (const event of stream.events) {
        if (event.type === "delta") cancellation.abort();
        expect(event.type).toBeDefined();
      }
      expect(upstreamSignal?.aborted).toBe(false);
      const settled = await credits.snapshot(user);
      expect(settled.used).toBe(before * 2);
      expect(settled.pending).toBe(0);
      expect(settled.reserved).toBe(0);
      mode = "error";
      const id = newEntityId();
      await expect(ai.complete(user, { ...input, operationId: id })).rejects.toThrow();
      expect(calls).toBe(3);
      expect((await credits.snapshot(user)).pending).toBe(0);
      await expect(
        ai.complete(user, { ...input, operationId: id }),
      ).rejects.toMatchObject({ code: "OPERATION_FINALIZED" });
      expect(calls).toBe(3);
    });
    it("keeps missing usage pending through replay and preserves terminal usage on cancellation", async () => {
      const user = await actor();
      const config = loadConfig({
        ...process.env,
        NODE_ENV: "test",
        DEEPSEEK_API_KEY: "test",
      });
      let mode = "missing",
        calls = 0;
      const client = createDeepSeekClient(config, async () => {
        await Promise.resolve();
        calls++;
        const metadata =
          "data: " +
          JSON.stringify({
            id: "edge",
            model: req.model,
            choices: [{ delta: { content: "hello" } }],
          }) +
          "\n\n";
        const metering =
          "data: " +
          JSON.stringify({
            choices: [],
            usage: {
              prompt_tokens: 5000,
              prompt_cache_hit_tokens: 4000,
              prompt_cache_miss_tokens: 1000,
              completion_tokens: 500,
              total_tokens: 5500,
            },
          }) +
          "\n\n";
        return new Response(
          metadata +
            (mode === "missing"
              ? "data: [DONE]\n\n"
              : mode === "truncated"
                ? ""
                : metering + "data: [DONE]\n\n"),
        );
      });
      const ai = createAiService(
        config,
        runtime.database,
        runtime.redis,
        createBillingService(runtime.database),
        client,
      );
      const input = {
        task: "conversation",
        operationId: newEntityId(),
        messages: req.messages,
        responseFormat: "text" as const,
        maxOutputTokens: 500,
      };
      const first = await ai.stream(user, input);
      for await (const event of first.events) expect(event.type).toBeDefined();
      const pending = (await credits.snapshot(user)).pending;
      expect(pending).toBe(0);
      expect((await credits.snapshot(user)).remaining).toBe(100);
      const replay = await ai.stream(user, input);
      for await (const event of replay.events) expect(event.type).not.toBe("usage");
      expect(calls).toBe(1);
      expect((await credits.snapshot(user)).pending).toBe(pending);
      mode = "truncated";
      const truncated = await ai.stream(user, { ...input, operationId: newEntityId() });
      await expect(
        (async () => {
          for await (const event of truncated.events) expect(event.type).toBeDefined();
        })(),
      ).rejects.toMatchObject({ code: "AI_UPSTREAM_PROTOCOL_ERROR" });
      expect((await credits.snapshot(user)).pending).toBe(0);
      expect((await credits.snapshot(user)).remaining).toBe(100);
      const [unknown] = await runtime.database.sql<{ count: number }[]>`
        select count(*)::int as count from app.credit_operations where user_id=${user} and status='pending'`;
      expect(unknown?.count).toBe(2);
      mode = "metered";
      const metered = await ai.stream(user, { ...input, operationId: newEntityId() });
      for await (const event of metered.events) {
        if (event.type === "usage") break;
      }
      expect((await credits.snapshot(user)).used).toBeGreaterThan(0);
    });
  },
);
