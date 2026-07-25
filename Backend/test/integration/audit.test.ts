import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { registerDomainRoutes } from "../../src/modules/domain/routes.js";
import { createDomainService } from "../../src/modules/domain/service.js";
import type { UserSnapshot } from "../../src/modules/domain/types.js";
import { registerAuditHooks } from "../../src/modules/observability/audit.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("persistent audit events", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  const requestIds: string[] = [];
  const verificationTokens = new Map<string, string>();
  const email = `audit-${newEntityId()}@example.com`;
  const password = "Correct Horse Audit 1!";

  beforeAll(async () => {
    const config = loadConfig({ NODE_ENV: "test" });
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
    const domainService = createDomainService(dependencies.database);
    app = await buildApp(config, { logger: false });
    registerAuditHooks(app, config, dependencies.database);
    registerAuthRoutes(app, authService);
    registerDomainRoutes(app, authService, domainService, {
      enableDebugRoutes: true,
    });

    const registration = await app.inject({
      method: "POST",
      payload: { email, password },
      url: "/v1/auth/register",
    });
    requestIds.push(String(registration.headers["x-request-id"]));
    expect(await jobWorker.runOnce()).toBe("succeeded");
    const verification = await app.inject({
      method: "POST",
      payload: { token: verificationTokens.get(email) },
      url: "/v1/auth/email/verify",
    });
    requestIds.push(String(verification.headers["x-request-id"]));
    const login = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "audit-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    requestIds.push(String(login.headers["x-request-id"]));
    const tokens = login.json<TokenResponse>();
    accessToken = tokens.accessToken;
    userId = tokens.userId;
  });

  afterAll(async () => {
    await app.close();
    for (const requestId of requestIds) {
      await dependencies.database.sql`
        delete from app.audit_events
        where request_id = ${requestId}
      `;
    }
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
    `;
    await dependencies.close();
  });

  it("records mutation identity and outcome without request payloads", async () => {
    const authorization = { authorization: `Bearer ${accessToken}` };
    const snapshotResponse = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/v1/me",
    });
    const snapshot = snapshotResponse.json<UserSnapshot>();
    const privateDisplayName = "不要进入审计日志";
    const update = await app.inject({
      headers: {
        ...authorization,
        "idempotency-key": newEntityId(),
      },
      method: "PATCH",
      payload: {
        displayName: privateDisplayName,
        expectedVersion: snapshot.profile.version,
      },
      url: "/v1/me",
    });
    expect(update.statusCode).toBe(200);
    const requestId = String(update.headers["x-request-id"]);
    requestIds.push(requestId);

    const readEvent = async () => {
      const [event] = await dependencies.database.sql<
        {
          action: string;
          actor_kind: string;
          actor_user_id: string;
          ip_hash: string;
          metadata_text: string;
          outcome: string;
        }[]
      >`
        select
          action,
          actor_kind,
          actor_user_id::text,
          outcome,
          ip_hash,
          metadata::text as metadata_text
        from app.audit_events
        where request_id = ${requestId}
      `;
      return event;
    };
    await expect.poll(readEvent, { timeout: 2000 }).toBeDefined();
    const event = await readEvent();
    expect(event).toMatchObject({
      action: "PATCH /v1/me",
      actor_kind: "user",
      actor_user_id: userId,
      outcome: "success",
    });
    expect(event?.ip_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(event?.metadata_text).toBe('{"statusCode": 200}');
    expect(event?.metadata_text).not.toContain(privateDisplayName);
  });
});
