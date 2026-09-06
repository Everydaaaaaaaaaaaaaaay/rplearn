import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { registerAiAdminRoutes } from "../../src/modules/ai/admin-routes.js";
import { createAiConfigService } from "../../src/modules/ai/config-service.js";
import type { AiManagedRoute, AiRouteSettings } from "../../src/modules/ai/types.js";
import { registerAuditHooks } from "../../src/modules/observability/audit.js";
import { newEntityId } from "../../src/shared/id.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

describe.runIf(runIntegrationTests)("managed AI route configuration", () => {
  const operatorKeyId = "integration-operator";
  const operatorToken = "integration-admin-token-with-more-than-32-characters";
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;

  const authorization = {
    authorization: `Bearer ${operatorToken}`,
  };

  beforeAll(async () => {
    const config = loadConfig({
      ADMIN_API_ENABLED: "true",
      ADMIN_API_KEYS: `${operatorKeyId}=${operatorToken}`,
      NODE_ENV: "test",
    });
    dependencies = createRuntimeDependencies(config);
    await runMigrations(dependencies.database);
    await dependencies.start();
    app = await buildApp(config, { logger: false });
    registerAuditHooks(app, config, dependencies.database);
    registerAiAdminRoutes(
      app,
      createAdminAuthenticator(config.adminApiKeys),
      createAiConfigService(config, dependencies.database),
    );
  });

  afterAll(async () => {
    await app.close();
    await dependencies.database.sql`
      delete from app.audit_events
      where metadata ->> 'operatorKeyId' = ${operatorKeyId}
    `;
    await dependencies.close();
  });

  it("requires an operator key and versions, audits, retries, and rolls back changes", async () => {
    const denied = await app.inject({
      method: "GET",
      url: "/internal/admin/ai/routes",
    });
    expect(denied.statusCode).toBe(401);

    const initialResponse = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/internal/admin/ai/routes",
    });
    expect(initialResponse.statusCode).toBe(200);
    const initial = initialResponse
      .json<{ routes: readonly AiManagedRoute[] }>()
      .routes.find((route) => route.task === "conversation");
    expect(initial).toBeDefined();
    if (initial === undefined) {
      return;
    }
    const originalSettings = settings(initial);
    const changedSettings: AiRouteSettings = {
      ...originalSettings,
      temperature: originalSettings.temperature === 0.8 ? 0.7 : 0.8,
    };
    const updateCommand = newEntityId();
    const updatePayload = {
      changeReason: "Tune conversation sampling after evaluated canary",
      expectedVersion: initial.configVersion,
      settings: changedSettings,
    };
    const updatedResponse = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": updateCommand,
      },
      method: "PUT",
      payload: updatePayload,
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(updatedResponse.statusCode).toBe(200);
    const updated = updatedResponse.json<AiManagedRoute>();
    expect(updated.configVersion).toBe(initial.configVersion + 1);
    expect(updated.temperature).toBe(changedSettings.temperature);

    const retry = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": updateCommand,
      },
      method: "PUT",
      payload: updatePayload,
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(retry.json()).toEqual(updatedResponse.json());

    const conflictingRetry = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": updateCommand,
      },
      method: "PUT",
      payload: {
        ...updatePayload,
        changeReason: "A different operation reusing the same command ID",
      },
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(conflictingRetry.statusCode).toBe(409);
    expect(conflictingRetry.json<{ code: string }>().code).toBe(
      "IDEMPOTENCY_KEY_CONFLICT",
    );

    const stale = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": newEntityId(),
      },
      method: "PUT",
      payload: updatePayload,
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(stale.statusCode).toBe(409);
    expect(stale.json<{ code: string }>().code).toBe("AI_ROUTE_VERSION_CONFLICT");

    const history = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/internal/admin/ai/routes/conversation/revisions?limit=10",
    });
    expect(history.statusCode).toBe(200);
    expect(
      history.json<{
        revisions: readonly {
          configVersion: number;
          operatorKeyId: string;
        }[];
      }>().revisions,
    ).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          configVersion: updated.configVersion,
          operatorKeyId,
        }),
      ]),
    );

    const rollback = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": newEntityId(),
      },
      method: "POST",
      payload: {
        changeReason: "Rollback after canary verification failed acceptance",
        expectedVersion: updated.configVersion,
        targetVersion: initial.configVersion,
      },
      url: "/internal/admin/ai/routes/conversation/rollback",
    });
    expect(rollback.statusCode).toBe(200);
    expect(settings(rollback.json<AiManagedRoute>())).toEqual(originalSettings);
    expect(rollback.json<AiManagedRoute>().configVersion).toBe(
      initial.configVersion + 2,
    );

    const auditRows = await dependencies.database.sql<
      { actor_kind: string; operator_key_id: string | null }[]
    >`
      select
        actor_kind,
        metadata ->> 'operatorKeyId' as operator_key_id
      from app.audit_events
      where action in (
          'PUT /internal/admin/ai/routes/:task',
          'POST /internal/admin/ai/routes/:task/rollback'
        )
        and outcome = 'success'
      order by created_at
    `;
    expect(auditRows).toEqual(
      expect.arrayContaining([
        { actor_kind: "operator", operator_key_id: operatorKeyId },
      ]),
    );
  }, 30_000);

  it("rejects models outside runtime policy and provider option injection", async () => {
    const response = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/internal/admin/ai/routes",
    });
    const route = response
      .json<{ routes: readonly AiManagedRoute[] }>()
      .routes.find((candidate) => candidate.task === "conversation");
    expect(route).toBeDefined();
    if (route === undefined) {
      return;
    }

    const disallowedModel = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": newEntityId(),
      },
      method: "PUT",
      payload: {
        changeReason: "Attempt a model outside the deployment allowlist",
        expectedVersion: route.configVersion,
        settings: {
          ...settings(route),
          model: "deepseek-v4-pro",
        },
      },
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(disallowedModel.statusCode).toBe(409);
    expect(disallowedModel.json<{ code: string }>().code).toBe("AI_MODEL_NOT_ALLOWED");

    const injectedOption = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": newEntityId(),
      },
      method: "PUT",
      payload: {
        changeReason: "Attempt to override a controlled request field",
        expectedVersion: route.configVersion,
        settings: {
          ...settings(route),
          providerOptions: {
            model: "attacker-controlled-model",
          },
        },
      },
      url: "/internal/admin/ai/routes/conversation",
    });
    expect(injectedOption.statusCode).toBe(400);
    expect(injectedOption.json<{ code: string }>().code).toBe("INVALID_REQUEST");
  });

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
