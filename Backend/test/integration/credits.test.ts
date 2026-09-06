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
    it("serializes competing requests and never dispatches a replay", async () => {
      const user = await actor(),
        ids = Array.from({ length: 8 }, () => newEntityId());
      const results = await Promise.allSettled(
        ids.map((id) => credits.reserve(user, id, id, req)),
      );
      const accepted = ids.filter((_, i) => results[i]?.status === "fulfilled");
      expect(accepted.length).toBe(3);
      expect((await credits.snapshot(user)).reserved).toBeLessThanOrEqual(100);
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
    it("retains uncertain holds across resets, releases only undispatched work, and requires reconciliation evidence", async () => {
      const user = await actor(),
        pending = newEntityId(),
        unused = newEntityId();
      await credits.reserve(user, pending, pending, req);
      await credits.dispatch(user, pending);
      await credits.reserve(user, unused, unused, req);
      await runtime.database
        .sql`update app.credit_operations set expires_at=now()-interval '1 second',window_key='day:2000-01-01' where user_id=${user}`;
      const snapshot = await credits.snapshot(user);
      expect(snapshot.pending).toBeGreaterThan(0);
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
      const config = loadConfig({
        ...process.env,
        NODE_ENV: "test",
        DEEPSEEK_API_KEY: "test",
      });
      const client = createDeepSeekClient(config, async () => {
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
                model: req.model,
                choices: [{ delta: { content: "hello" } }],
              }) +
              "\n\ndata: " +
              JSON.stringify({ choices: [], usage: raw }) +
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
      const stream = await ai.stream(user, { ...input, operationId: newEntityId() });
      for await (const event of stream.events) {
        expect(event.type).toBeDefined();
      }
      expect((await credits.snapshot(user)).used).toBe(before * 2);
      mode = "error";
      const id = newEntityId();
      await expect(ai.complete(user, { ...input, operationId: id })).rejects.toThrow();
      expect(calls).toBe(3);
      expect((await credits.snapshot(user)).pending).toBeGreaterThan(0);
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
      expect(pending).toBeGreaterThan(0);
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
      expect((await credits.snapshot(user)).pending).toBeGreaterThan(pending);
      mode = "metered";
      const metered = await ai.stream(user, { ...input, operationId: newEntityId() });
      for await (const event of metered.events) {
        if (event.type === "usage") break;
      }
      expect((await credits.snapshot(user)).used).toBeGreaterThan(0);
    });
  },
);
