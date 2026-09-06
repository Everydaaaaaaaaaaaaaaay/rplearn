import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { DeepSeekClient } from "../../src/modules/ai/deepseek/client.js";
import { registerAiRoutes } from "../../src/modules/ai/routes.js";
import { createAiService } from "../../src/modules/ai/service.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { createBillingService } from "../../src/modules/billing/service.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("AI gateway", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let guestUserId: string | undefined;
  let userId: string;
  const verificationTokens = new Map<string, string>();
  const email = `ai-${newEntityId()}@example.com`;
  const password = "Correct Horse AI Gateway 1!";

  beforeAll(async () => {
    const config = loadConfig({
      ...process.env,
      AI_USER_MINUTE_LIMIT: "20",
      AI_GUEST_ACCESS_ENABLED: "true",
      DEEPSEEK_API_KEY: "integration-test-key",
      NODE_ENV: "test",
    });
    dependencies = createRuntimeDependencies(config);
    await runMigrations(dependencies.database);
    await dependencies.start();
    const notifier: AuthNotifier = {
      sendEmailVerification: (destination, token) => {
        verificationTokens.set(destination, token);
        return Promise.resolve();
      },
      sendPasswordReset: () => Promise.resolve(),
    };
    const authService = await createAuthService(config, dependencies.database);
    const jobWorker = createTestJobWorker(config, dependencies.database, notifier);
    const billingService = createBillingService(dependencies.database);
    const deepSeek: DeepSeekClient = {
      complete: () =>
        Promise.resolve({
          content: "Hello from the gateway",
          model: "deepseek-v4-flash",
          providerRequestId: "deepseek-completion-1",
          usage: {
            inputTokens: 3,
            outputTokens: 2,
            totalTokens: 5,
          },
        }),
      configured: true,
      stream: () =>
        Promise.resolve(
          (async function* () {
            await Promise.resolve();
            yield {
              model: "deepseek-v4-flash",
              providerRequestId: "deepseek-stream-1",
              type: "metadata" as const,
            };
            yield { text: "你", type: "delta" as const };
            yield { text: "好", type: "delta" as const };
            yield {
              type: "usage" as const,
              usage: {
                inputTokens: 4,
                outputTokens: 3,
                totalTokens: 7,
              },
            };
            yield { type: "done" as const };
          })(),
        ),
    };
    const aiService = createAiService(
      config,
      dependencies.database,
      dependencies.redis,
      billingService,
      deepSeek,
    );
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerAiRoutes(app, authService, aiService, {
      guestAccessEnabled: config.aiGuestAccessEnabled,
    });

    await app.inject({
      method: "POST",
      payload: { email, password },
      url: "/v1/auth/register",
    });
    expect(await jobWorker.runOnce()).toBe("succeeded");
    await app.inject({
      method: "POST",
      payload: { token: verificationTokens.get(email) },
      url: "/v1/auth/email/verify",
    });
    const login = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "ai-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    const tokens = login.json<TokenResponse>();
    accessToken = tokens.accessToken;
    userId = tokens.userId;
  });

  afterAll(async () => {
    await app.close();
    await dependencies.database.sql`
      delete from app.jobs
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.auth_security_events
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.users
      where id = ${userId}
         or id = ${guestUserId ?? userId}
    `;
    await dependencies.close();
  });

  it("routes completion and streaming without persisting content", async () => {
    const authorization = { authorization: `Bearer ${accessToken}` };
    const completion = await app.inject({
      headers: authorization,
      method: "POST",
      payload: {
        messages: [
          { content: "System instructions must stay private", role: "system" },
          { content: "Say hello", role: "user" },
        ],
        task: "conversation",
      },
      url: "/v1/ai/completions",
    });
    expect(completion.statusCode).toBe(200);
    const completionBody = completion.json<{
      content: string;
      model: string;
      requestId: string;
    }>();
    expect(completionBody).toMatchObject({
      content: "Hello from the gateway",
      model: "deepseek-v4-flash",
    });
    expect(completionBody.requestId).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/i);

    const stream = await app.inject({
      headers: authorization,
      method: "POST",
      payload: {
        messages: [{ content: "Greet me in Chinese", role: "user" }],
        task: "conversation",
      },
      url: "/v1/ai/stream",
    });
    expect(stream.statusCode).toBe(200);
    expect(stream.headers["content-type"]).toContain("text/event-stream");
    expect(stream.body).toContain('event: delta\ndata: {"text":"你"}');
    expect(stream.body).toContain('event: delta\ndata: {"text":"好"}');
    expect(stream.body).toContain("event: done");

    const [usage] = await dependencies.database.sql<
      {
        input_tokens: number;
        output_tokens: number;
        request_count: number;
      }[]
    >`
      select input_tokens, output_tokens, request_count
      from app.ai_daily_usage
      where user_id = ${userId}
        and usage_date = (now() at time zone 'utc')::date
    `;
    expect(usage).toEqual({
      input_tokens: 7,
      output_tokens: 5,
      request_count: 2,
    });

    const requestRows = await dependencies.database.sql<
      { error_code: string | null; status: string }[]
    >`
      select status, error_code
      from app.ai_requests
      where user_id = ${userId}
      order by requested_at
    `;
    expect(requestRows).toEqual([
      { error_code: null, status: "succeeded" },
      { error_code: null, status: "succeeded" },
    ]);

    const contentColumns = await dependencies.database.sql<{ column_name: string }[]>`
      select column_name
      from information_schema.columns
      where table_schema = 'app'
        and table_name = 'ai_requests'
        and column_name in ('content', 'messages', 'prompt', 'response')
    `;
    expect(contentColumns).toEqual([]);
  }, 30_000);

  it("allows a device-scoped guest to use AI without an account session", async () => {
    const response = await app.inject({
      headers: { "x-lingotrip-guest-id": "integration-guest-device" },
      method: "POST",
      payload: {
        messages: [{ content: "Say hello", role: "user" }],
        task: "conversation",
      },
      url: "/v1/ai/completions",
    });
    expect(response.statusCode).toBe(200);
    expect(response.json<{ content: string }>().content).toBe("Hello from the gateway");

    const [principal] = await dependencies.database.sql<{ user_id: string }[]>`
      select user_id::text
      from app.ai_guest_principals
      where device_reference is not null
      order by created_at desc
      limit 1
    `;
    expect(principal?.user_id).toBeDefined();
    guestUserId = principal?.user_id;
  });

  it("enforces the unified cost credit budget", async () => {
    await dependencies.database.sql`
      insert into app.credit_operations(user_id,operation_id,request_hash,task,window_key,plan,policy_version,reserved_units,settled_units,status,price,expires_at)
      values (${userId},${newEntityId()},'test-exhaustion','conversation', 'day:' || to_char(now() at time zone 'utc','YYYY-MM-DD'),'free','test',100000000,100000000,'settled','{}',now())
    `;
    const response = await app.inject({
      headers: { authorization: `Bearer ${accessToken}` },
      method: "POST",
      payload: {
        messages: [{ content: "One request too many", role: "user" }],
        task: "conversation",
      },
      url: "/v1/ai/completions",
    });
    expect(response.statusCode).toBe(429);
    expect(response.json<{ code: string }>().code).toBe("CREDITS_EXHAUSTED");
  });

  it("seeds every initial task to DeepSeek v4 Flash", async () => {
    const routes = await dependencies.database.sql<
      {
        model: string;
        provider: string;
        thinkingMode: string | null;
      }[]
    >`
      select
        model,
        provider,
        provider_options #>> '{thinking,type}' as "thinkingMode"
      from app.ai_routes
      where enabled = true
      group by model, provider, provider_options #>> '{thinking,type}'
    `;
    expect(routes).toEqual([
      {
        model: "deepseek-v4-flash",
        provider: "deepseek",
        thinkingMode: "disabled",
      },
    ]);
  });
});
