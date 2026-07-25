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
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import { registerSyncRoutes } from "../../src/modules/sync/routes.js";
import { createSyncService } from "../../src/modules/sync/service.js";
import type { SyncPage, SyncSnapshot } from "../../src/modules/sync/types.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("cross-device synchronization", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  const verificationTokens = new Map<string, string>();
  const email = `sync-${newEntityId()}@example.com`;
  const password = "Correct Horse Sync 1!";

  const headers = () => ({
    authorization: `Bearer ${accessToken}`,
  });

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
    const syncService = createSyncService(
      dependencies.database,
      domainService,
      createSyncCursorCodec(config.authTokenHashPepper),
    );
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerDomainRoutes(app, authService, domainService, {
      enableDebugRoutes: true,
    });
    registerSyncRoutes(app, authService, syncService);

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
          deviceId: "sync-test-device-a",
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
    `;
    await dependencies.close();
  });

  it("bootstraps, applies offline commands, pages events, and rejects tampering", async () => {
    const bootstrapResponse = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/sync/snapshot",
    });
    expect(bootstrapResponse.statusCode).toBe(200);
    const bootstrap = bootstrapResponse.json<SyncSnapshot>();
    expect(bootstrap.state.profile.currentRegionId).toBe("london");

    const commandId = newEntityId();
    const commandPayload = {
      commands: [
        {
          commandId,
          payload: {
            displayName: "第二台设备",
            expectedVersion: bootstrap.state.profile.version,
          },
          type: "profile.update",
        },
      ],
    };
    const upload = await app.inject({
      headers: headers(),
      method: "POST",
      payload: commandPayload,
      url: "/v1/sync/commands",
    });
    expect(upload.statusCode).toBe(200);
    const uploadBody = upload.json<{
      results: readonly {
        commandId: string;
        result: unknown;
        status: string;
      }[];
    }>();
    expect(uploadBody.results).toHaveLength(1);
    expect(uploadBody.results[0]).toMatchObject({
      commandId,
      status: "applied",
    });
    expect(uploadBody.results[0]?.result).toBeTypeOf("object");

    const retry = await app.inject({
      headers: headers(),
      method: "POST",
      payload: commandPayload,
      url: "/v1/sync/commands",
    });
    expect(retry.json<unknown>()).toEqual(uploadBody);

    const changesResponse = await app.inject({
      headers: headers(),
      method: "GET",
      url: `/v1/sync/changes?cursor=${encodeURIComponent(bootstrap.cursor)}&limit=1`,
    });
    expect(changesResponse.statusCode).toBe(200);
    const page = changesResponse.json<SyncPage>();
    expect(page.changes).toHaveLength(1);
    expect(page.changes[0]).toMatchObject({
      commandId,
      eventType: "profile.update",
      payload: {
        displayName: "第二台设备",
      },
      sequence: "1",
    });
    expect(page.hasMore).toBe(false);

    const noDuplicateResponse = await app.inject({
      headers: headers(),
      method: "GET",
      url: `/v1/sync/changes?cursor=${encodeURIComponent(page.nextCursor)}`,
    });
    expect(noDuplicateResponse.json<SyncPage>().changes).toEqual([]);

    const refreshed = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/sync/snapshot",
    });
    expect(refreshed.json<{ state: UserSnapshot }>().state.profile.displayName).toBe(
      "第二台设备",
    );

    const tamperedCursor = `${page.nextCursor.slice(0, -1)}x`;
    const tampered = await app.inject({
      headers: headers(),
      method: "GET",
      url: `/v1/sync/changes?cursor=${encodeURIComponent(tamperedCursor)}`,
    });
    expect(tampered.statusCode).toBe(400);
    expect(tampered.json<{ code: string }>().code).toBe("INVALID_SYNC_CURSOR");
  }, 30_000);
});
