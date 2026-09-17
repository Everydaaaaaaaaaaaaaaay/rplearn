import { isDeepStrictEqual } from "node:util";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { registerAiAdminConsoleRoutes } from "../../src/modules/ai/admin-console.js";
import { registerAiAdminRoutes } from "../../src/modules/ai/admin-routes.js";
import { AiAnalyticsRepository } from "../../src/modules/ai/analytics-repository.js";
import { AiCatalogRepository } from "../../src/modules/ai/catalog-repository.js";
import { createAiCatalogService } from "../../src/modules/ai/catalog-service.js";
import { createAiConfigService } from "../../src/modules/ai/config-service.js";
import { createAiService } from "../../src/modules/ai/service.js";
import type { DeepSeekClient } from "../../src/modules/ai/deepseek/client.js";
import type { OpenRouterClient } from "../../src/modules/ai/openrouter/client.js";
import type { AiManagedRoute, AiRouteSettings } from "../../src/modules/ai/types.js";
import { registerAuditHooks } from "../../src/modules/observability/audit.js";
import { newEntityId } from "../../src/shared/id.js";
import { createBillingService } from "../../src/modules/billing/service.js";
import { createCreditService } from "../../src/modules/access/credit-service.js";
import { integrationConfig } from "../helpers/integration.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

describe.runIf(runIntegrationTests)("AI operations console", () => {
  const operatorToken = "console-admin-token-with-more-than-32-characters";
  const operatorKeyId = "console-test";
  const auth = { authorization: `Bearer ${operatorToken}` };
  let app: FastifyInstance;
  let catalog: ReturnType<typeof createAiCatalogService>;
  let config: ReturnType<typeof integrationConfig>;
  let openRouter: OpenRouterClient;
  let runtime: RuntimeDependencies;
  let userId: string;

  beforeAll(async () => {
    config = integrationConfig({
      ...process.env,
      ADMIN_API_ENABLED: "true",
      ADMIN_API_KEYS: `${operatorKeyId}=${operatorToken}`,
      NODE_ENV: "test",
      DEEPSEEK_API_KEY: "test-deepseek-key",
      OPENROUTER_API_KEY: "test-openrouter-key",
      OPENROUTER_USD_TO_CNY: "7.2",
    });
    runtime = createRuntimeDependencies(config);
    await runMigrations(runtime.database);
    await runtime.start();
    openRouter = {
      complete: async (request) => {
        await request.onAttempt?.();
        return {
          content: "Hello from Ling",
          model: "inclusionai/ling-3.0-flash",
          providerRequestId: "openrouter-generation-1",
          usage: {
            cacheHitTokens: 80,
            cacheMissTokens: 20,
            inputTokens: 100,
            outputTokens: 20,
            providerCostUsd: "0.0001",
            totalTokens: 120,
          },
        };
      },
      configured: true,
      models: () =>
        Promise.resolve([
          {
            architecture: { input_modalities: ["text"], output_modalities: ["text"] },
            cachedInputPriceUsd: "0.0000000042",
            completionPriceUsd: "0.000000063",
            contextLength: 262_144,
            id: "inclusionai/ling-3.0-flash",
            name: "inclusionAI: Ling 3.0 Flash",
            promptPriceUsd: "0.000000021",
            supportedParameters: ["response_format", "temperature"],
          },
          {
            architecture: {
              input_modalities: ["text"],
              output_modalities: ["image"],
            },
            cachedInputPriceUsd: null,
            completionPriceUsd: "0.000001",
            contextLength: 32_768,
            id: "image-only/model",
            name: "Image-only model",
            promptPriceUsd: "0.000001",
            supportedParameters: ["temperature"],
          },
          {
            architecture: {},
            cachedInputPriceUsd: null,
            completionPriceUsd: "-1",
            contextLength: null,
            id: "not-billable/model",
            name: "Unavailable model",
            promptPriceUsd: "-1",
            supportedParameters: [],
          },
        ]),
      stream: () => Promise.reject(new Error("not used")),
    };
    catalog = createAiCatalogService(
      config,
      new AiCatalogRepository(runtime.database),
      openRouter,
    );
    app = await buildApp(config, { logger: false });
    registerAuditHooks(app, config, runtime.database);
    registerAiAdminConsoleRoutes(app);
    registerAiAdminRoutes(
      app,
      createAdminAuthenticator(config.adminApiKeys),
      createAiConfigService(config, runtime.database, catalog),
      {
        analytics: new AiAnalyticsRepository(runtime.database),
        catalog,
      },
    );
    userId = newEntityId();
    await runtime.database.sql`insert into app.users(id) values(${userId})`;
  });

  afterAll(async () => {
    await app.close();
    await runtime.database.sql`delete from app.users where id=${userId}`;
    await runtime.database
      .sql`delete from app.audit_events where metadata ->> 'operatorKeyId'=${operatorKeyId}`;
    await runtime.close();
  });

  it("serves a locked-down console and protects its data APIs", async () => {
    const page = await app.inject({ method: "GET", url: "/internal/admin/ai" });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain("模型控制台");
    expect(page.body).toContain("一键切换全部模型");
    expect(page.headers["content-security-policy"]).toContain("default-src 'none'");
    expect(
      (await app.inject({ method: "GET", url: "/internal/admin/ai/models" }))
        .statusCode,
    ).toBe(401);
    expect(
      (await app.inject({ method: "GET", url: "/internal/admin/ai/analytics" }))
        .statusCode,
    ).toBe(401);
  });

  it("refreshes the live catalog and publishes an audited OpenRouter route", async () => {
    const refreshed = await app.inject({
      headers: auth,
      method: "POST",
      url: "/internal/admin/ai/models/openrouter/refresh",
    });
    expect(refreshed.statusCode).toBe(200);
    expect(refreshed.json<{ models: readonly { model: string }[] }>().models).toEqual([
      expect.objectContaining({ model: "inclusionai/ling-3.0-flash" }),
    ]);

    const routes = await app.inject({
      headers: auth,
      method: "GET",
      url: "/internal/admin/ai/routes",
    });
    const route = routes
      .json<{ routes: readonly AiManagedRoute[] }>()
      .routes.find((candidate) => candidate.task === "conversation");
    if (route === undefined) throw new Error("missing conversation route");
    const original = settings(route);
    const update = await app.inject({
      headers: { ...auth, "idempotency-key": newEntityId() },
      method: "PUT",
      payload: {
        changeReason: "Canary Ling conversation quality evaluation",
        expectedVersion: route.configVersion,
        settings: {
          ...original,
          model: "inclusionai/ling-3.0-flash",
          provider: "openrouter",
          providerOptions: { provider: { require_parameters: true } },
        },
      },
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(update.statusCode).toBe(200);
    const updated = update.json<AiManagedRoute>();
    expect(updated).toMatchObject({
      model: "inclusionai/ling-3.0-flash",
      provider: "openrouter",
    });

    const canaryUser = newEntityId();
    await runtime.database.sql`insert into app.users(id) values(${canaryUser})`;
    const deepSeek: DeepSeekClient = {
      complete: () =>
        Promise.reject(new Error("DeepSeek must not receive this request")),
      configured: true,
      stream: () => Promise.reject(new Error("not used")),
    };
    const ai = createAiService(
      config,
      runtime.database,
      runtime.redis,
      createBillingService(runtime.database),
      deepSeek,
      { catalog, openRouter },
    );
    const canaryOperationId = newEntityId();
    await expect(
      ai.complete(canaryUser, {
        maxOutputTokens: 20,
        messages: [{ content: "Hello", role: "user" }],
        operationId: canaryOperationId,
        responseFormat: "text",
        task: "conversation",
      }),
    ).resolves.toMatchObject({ content: "Hello from Ling" });
    const credits = createCreditService(runtime.database, catalog.resolveCreditPrice);
    expect((await credits.snapshot(canaryUser)).used).toBe(0.72);
    await runtime.database.sql`
      update app.ai_model_catalog
      set available=false
      where provider='openrouter' and model='inclusionai/ling-3.0-flash'
    `;
    await expect(
      ai.complete(canaryUser, {
        maxOutputTokens: 20,
        messages: [{ content: "Hello", role: "user" }],
        operationId: canaryOperationId,
        responseFormat: "text",
        task: "conversation",
      }),
    ).resolves.toMatchObject({ content: "Hello from Ling" });
    expect((await credits.snapshot(canaryUser)).used).toBe(0.72);
    await runtime.database.sql`delete from app.users where id=${canaryUser}`;

    const rollback = await app.inject({
      headers: { ...auth, "idempotency-key": newEntityId() },
      method: "POST",
      payload: {
        changeReason: "Restore baseline after console integration test",
        expectedVersion: updated.configVersion,
        targetVersion: route.configVersion,
      },
      url: "/internal/admin/ai/routes/conversation/rollback",
    });
    expect(rollback.statusCode).toBe(200);
    expect(settings(rollback.json<AiManagedRoute>())).toEqual(original);
  });

  it("rejects OpenRouter JSON routes without strict parameter support", async () => {
    const response = await app.inject({
      headers: auth,
      method: "GET",
      url: "/internal/admin/ai/routes",
    });
    const route = response
      .json<{ routes: readonly AiManagedRoute[] }>()
      .routes.find((candidate) => candidate.task === "quiz");
    if (route === undefined) throw new Error("missing quiz route");

    const update = await app.inject({
      headers: { ...auth, "idempotency-key": newEntityId() },
      method: "PUT",
      payload: {
        changeReason: "Reject an unsafe OpenRouter JSON route",
        expectedVersion: route.configVersion,
        settings: {
          ...settings(route),
          model: "inclusionai/ling-3.0-flash",
          provider: "openrouter",
          providerOptions: {},
        },
      },
      url: "/internal/admin/ai/routes/quiz",
    });

    expect(update.statusCode).toBe(400);
    expect(update.json<{ code: string }>().code).toBe("INVALID_REQUEST");
  });

  it("rejects retired speech feedback before provider calls or credit operations", async () => {
    const complete = vi.fn<DeepSeekClient["complete"]>();
    const stream = vi.fn<DeepSeekClient["stream"]>();
    const ai = createAiService(
      config, runtime.database, runtime.redis, createBillingService(runtime.database),
      { configured: true, complete, stream }, { catalog, openRouter },
    );
    const operationId = newEntityId();
    const input = {
      operationId, task: "speech_feedback", responseFormat: "text" as const,
      messages: [{ role: "user" as const, content: "See you tomorrow." }],
    };
    await expect(ai.complete(userId, input)).rejects.toMatchObject({ code: "AI_TASK_RETIRED" });
    await expect(ai.stream(userId, input)).rejects.toMatchObject({ code: "AI_TASK_RETIRED" });
    expect(complete).not.toHaveBeenCalled();
    expect(stream).not.toHaveBeenCalled();
    expect(await runtime.database.sql`
      select operation_id from app.credit_operations where operation_id = ${operationId}
    `).toHaveLength(0);
  });

  it("aggregates total, model and per-user cost without treating unknowns as zero", async () => {
    const operationId = newEntityId();
    await runtime.database.sql`
      insert into app.credit_operations(
        user_id,operation_id,request_hash,task,billing_scope,plan,window_key,
        policy_version,reserved_units,settled_units,status,price,expires_at
      ) values(
        ${userId},${operationId},'console-cost','conversation','user','free',
        'day:2026-09-11','test',2000000,1500000,'settled','{}',now()
      )
    `;
    await runtime.database.sql`
      insert into app.ai_requests(
        id,user_id,operation_id,task,provider,model,config_version,input_characters,
        input_tokens,output_tokens,cache_hit_tokens,cache_miss_tokens,
        provider_cost_usd,status,provider_attempts,latency_ms,completed_at
      ) values(
        ${newEntityId()},${userId},${operationId},'conversation','openrouter',
        'inclusionai/ling-3.0-flash',1,100,1000,100,800,200,
        0.000208333333,'succeeded',1,420,now()
      )
    `;
    const response = await app.inject({
      headers: auth,
      method: "GET",
      url: `/internal/admin/ai/analytics?days=7&userId=${userId}`,
    });
    expect(response.statusCode).toBe(200);
    const body = response.json<{
      byModel: readonly { key: string }[];
      summary: { costCny: string; requests: number; users: number };
      users: readonly { costCny: string; key: string }[];
    }>();
    expect(body.summary).toMatchObject({ costCny: "0.001500", requests: 1, users: 1 });
    expect(body.byModel[0]?.key).toBe("openrouter/inclusionai/ling-3.0-flash");
    expect(body.users[0]).toMatchObject({ costCny: "0.001500", key: userId });
  });

  it("atomically switches every model, preserves task settings and supports safe retries", async () => {
    await catalog.refreshOpenRouter();
    const list = async () =>
      (
        await app.inject({
          headers: auth,
          method: "GET",
          url: "/internal/admin/ai/routes",
        })
      ).json<{ routes: AiManagedRoute[] }>().routes;
    const retiredBefore = await runtime.database.sql`
      select * from app.ai_routes where task = 'speech_feedback'
    `;
    expect(retiredBefore).toHaveLength(1);
    const initial = await list();
    expect(initial.some((route) => route.task === "translation")).toBe(true);
    // 单词弹窗例句翻译使用独立任务路由，与整句翻译分别控制。
    expect(
      initial.some((route) => route.task === "dictionary_example_translation"),
    ).toBe(true);
    expect(initial.some((route) => route.task === "speech_feedback")).toBe(false);
    const command = newEntityId();
    const payload = {
      provider: "openrouter",
      model: "inclusionai/ling-3.0-flash",
      changeReason: "Switch every task after batch model evaluation",
      expectedVersions: Object.fromEntries(
        initial.map((route) => [route.task, route.configVersion]),
      ),
    };
    const post = (body: unknown, id = newEntityId(), headers = auth) =>
      app.inject({
        headers: { ...headers, "idempotency-key": id },
        method: "POST",
        payload: body as Record<string, unknown>,
        url: "/internal/admin/ai/routes/switch-model",
      });
    expect(
      (await post(payload, newEntityId(), { authorization: "Bearer invalid" }))
        .statusCode,
    ).toBe(401);
    expect(
      (
        await app.inject({
          headers: auth,
          method: "POST",
          payload,
          url: "/internal/admin/ai/routes/switch-model",
        })
      ).statusCode,
    ).toBe(400);
    expect(
      (await post({ ...payload, expectedVersions: { conversation: 1 } })).statusCode,
    ).toBe(409);
    expect((await post({ ...payload, model: "missing/model" })).statusCode).toBe(409);
    expect(await list()).toEqual(initial);
    await runtime.database
      .sql`update app.ai_model_catalog set supported_parameters='[]'::jsonb where provider='openrouter' and model=${payload.model}`;
    try {
      const unsupported = await post(payload);
      expect(unsupported.statusCode).toBe(409);
      expect(unsupported.json<{ code: string }>().code).toBe(
        "AI_MODEL_CAPABILITY_MISSING",
      );
      expect(await list()).toEqual(initial);
    } finally {
      await catalog.refreshOpenRouter();
    }

    // A conflict in the last task must roll back writes and revisions for earlier tasks.
    const last = required(initial.at(-1));
    const stale = await post({
      ...payload,
      expectedVersions: {
        ...payload.expectedVersions,
        [last.task]: last.configVersion + 1,
      },
    });
    expect(stale.statusCode).toBe(409);
    expect(await list()).toEqual(initial);

    try {
      const response = await post(payload, command);
      expect(response.statusCode, response.body).toBe(200);
      const changed = response.json<{ routes: AiManagedRoute[] }>().routes;
      expect(changed).toHaveLength(initial.length);
      const retiredAfter = await runtime.database.sql`
        select * from app.ai_routes where task = 'speech_feedback'
      `;
      expect(retiredAfter).toEqual(retiredBefore);
      for (const original of initial) {
        const current = required(changed.find((route) => route.task === original.task));
        expect(current).toMatchObject({
          ...settings(original),
          provider: "openrouter",
          model: payload.model,
          providerOptions:
            original.provider === "openrouter"
              ? original.providerOptions
              : { provider: { require_parameters: true } },
          configVersion: original.configVersion + 1,
        });
        const history = (
          await app.inject({
            headers: auth,
            method: "GET",
            url: `/internal/admin/ai/routes/${original.task}/revisions`,
          })
        ).json<{ revisions: { operatorKeyId: string; changeReason: string }[] }>();
        expect(history.revisions[0]).toMatchObject({
          operatorKeyId,
          changeReason: payload.changeReason,
        });
      }
      expect((await post(payload, command)).json()).toEqual(response.json());
      expect(
        (
          await post(
            { ...payload, changeReason: "Different request with reused command key" },
            command,
          )
        ).statusCode,
      ).toBe(409);
      expect(await list()).toEqual(changed);

      // Two operators publishing the same snapshot: exactly one whole batch wins.
      const back = {
        ...payload,
        provider: "deepseek",
        model: "deepseek-v4-flash",
        expectedVersions: Object.fromEntries(
          changed.map((route) => [route.task, route.configVersion]),
        ),
      };
      const concurrent = await Promise.all([post(back), post(back)]);
      expect(concurrent.map((response) => response.statusCode).sort()).toEqual([
        200, 409,
      ]);
      for (const route of await list()) {
        expect(route.provider).toBe("deepseek");
        expect(route.providerOptions).toEqual({ thinking: { type: "disabled" } });
        expect(route.configVersion).toBe(
          required(initial.find((before) => before.task === route.task)).configVersion +
            2,
        );
      }
    } finally {
      for (const route of await list()) {
        const original = required(initial.find((before) => before.task === route.task));
        if (isDeepStrictEqual(settings(route), settings(original))) continue;
        const restored = await app.inject({
          headers: { ...auth, "idempotency-key": newEntityId() },
          method: "POST",
          url: `/internal/admin/ai/routes/${route.task}/rollback`,
          payload: {
            changeReason: "Restore original settings after batch integration test",
            expectedVersion: route.configVersion,
            targetVersion: original.configVersion,
          },
        });
        expect(restored.statusCode, restored.body).toBe(200);
      }
    }
  }, 30_000);

  function required<T>(value: T | undefined): T {
    if (value === undefined) throw new Error("Expected a route in the test fixture");
    return value;
  }

  function settings(route: AiManagedRoute): AiRouteSettings {
    return {
      allowJsonResponse: route.allowJsonResponse,
      enabled: route.enabled,
      maxInputCharacters: route.maxInputCharacters,
      maxMessages: route.maxMessages,
      maxOutputTokens: route.maxOutputTokens,
      model: route.model,
      provider: route.provider,
      providerOptions: route.providerOptions,
      temperature: route.temperature,
      timeoutMs: route.timeoutMs,
    };
  }
});
