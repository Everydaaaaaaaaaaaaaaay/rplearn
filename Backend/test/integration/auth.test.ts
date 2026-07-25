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
import { newEntityId } from "../../src/shared/id.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  accessTokenExpiresIn: number;
  refreshToken: string;
  refreshTokenExpiresAt: string;
  sessionId: string;
  tokenType: "Bearer";
  userId: string;
}>;

describe.runIf(runIntegrationTests)("email authentication", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  const verificationTokens = new Map<string, string>();
  const passwordResetTokens = new Map<string, string>();
  const email = `auth-${newEntityId()}@example.com`;
  const initialPassword = "Correct Horse Battery 1!";
  const replacementPassword = "Correct Horse Battery 2!";
  let userId: string | undefined;

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
      sendPasswordReset: (destination, token) => {
        passwordResetTokens.set(destination, token);
        return Promise.resolve();
      },
    };
    const authService = await createAuthService(config, dependencies.database, {
      notifier,
    });
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
  });

  afterAll(async () => {
    await app.close();
    if (userId !== undefined) {
      await dependencies.database.sql`
        delete from app.auth_security_events
        where user_id = ${userId}
      `;
      await dependencies.database.sql`
        delete from app.users
        where id = ${userId}
      `;
    }
    await dependencies.close();
  });

  it("registers, verifies, rotates, detects reuse, resets, and revokes", async () => {
    const registration = await app.inject({
      method: "POST",
      payload: {
        email,
        password: initialPassword,
      },
      url: "/v1/auth/register",
    });
    expect(registration.statusCode).toBe(202);
    expect(registration.json<{ status: string }>()).toEqual({
      status: "accepted",
    });

    const unverifiedLogin = await app.inject({
      method: "POST",
      payload: {
        device: {
          appVersion: "1.0",
          deviceId: "integration-device",
          platform: "ios",
        },
        email,
        password: initialPassword,
      },
      url: "/v1/auth/login",
    });
    expect(unverifiedLogin.statusCode).toBe(403);
    expect(unverifiedLogin.json<{ code: string }>().code).toBe("EMAIL_NOT_VERIFIED");

    const verificationToken = verificationTokens.get(email);
    expect(verificationToken).toBeTypeOf("string");
    const verification = await app.inject({
      method: "POST",
      payload: { token: verificationToken },
      url: "/v1/auth/email/verify",
    });
    expect(verification.statusCode).toBe(204);

    const login = await app.inject({
      method: "POST",
      payload: {
        device: {
          appVersion: "1.0",
          deviceId: "integration-device",
          deviceName: "Integration iPhone",
          platform: "ios",
        },
        email,
        password: initialPassword,
      },
      url: "/v1/auth/login",
    });
    expect(login.statusCode).toBe(200);
    const firstPair = login.json<TokenResponse>();
    userId = firstPair.userId;

    const sessions = await app.inject({
      headers: {
        authorization: `Bearer ${firstPair.accessToken}`,
      },
      method: "GET",
      url: "/v1/auth/sessions",
    });
    expect(sessions.statusCode).toBe(200);
    expect(
      sessions.json<{ sessions: readonly { current: boolean }[] }>().sessions,
    ).toEqual([expect.objectContaining({ current: true })]);

    const refresh = await app.inject({
      method: "POST",
      payload: {
        refreshToken: firstPair.refreshToken,
      },
      url: "/v1/auth/refresh",
    });
    expect(refresh.statusCode).toBe(200);
    const secondPair = refresh.json<TokenResponse>();
    expect(secondPair.refreshToken).not.toBe(firstPair.refreshToken);
    expect(secondPair.sessionId).toBe(firstPair.sessionId);

    const replay = await app.inject({
      method: "POST",
      payload: {
        refreshToken: firstPair.refreshToken,
      },
      url: "/v1/auth/refresh",
    });
    expect(replay.statusCode).toBe(401);
    expect(replay.json<{ code: string }>().code).toBe("REFRESH_TOKEN_REUSE_DETECTED");

    const compromisedAccess = await app.inject({
      headers: {
        authorization: `Bearer ${secondPair.accessToken}`,
      },
      method: "GET",
      url: "/v1/auth/sessions",
    });
    expect(compromisedAccess.statusCode).toBe(401);
    expect(compromisedAccess.json<{ code: string }>().code).toBe("SESSION_REVOKED");

    const forgot = await app.inject({
      method: "POST",
      payload: { email },
      url: "/v1/auth/password/forgot",
    });
    expect(forgot.statusCode).toBe(202);
    const resetToken = passwordResetTokens.get(email);
    expect(resetToken).toBeTypeOf("string");

    const reset = await app.inject({
      method: "POST",
      payload: {
        newPassword: replacementPassword,
        token: resetToken,
      },
      url: "/v1/auth/password/reset",
    });
    expect(reset.statusCode).toBe(204);

    const oldPasswordLogin = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "integration-device",
          platform: "ios",
        },
        email,
        password: initialPassword,
      },
      url: "/v1/auth/login",
    });
    expect(oldPasswordLogin.statusCode).toBe(401);

    const replacementLogin = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "integration-device",
          platform: "ios",
        },
        email,
        password: replacementPassword,
      },
      url: "/v1/auth/login",
    });
    expect(replacementLogin.statusCode).toBe(200);
    const replacementPair = replacementLogin.json<TokenResponse>();

    const sameDeviceLogin = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "integration-device",
          platform: "ios",
        },
        email,
        password: replacementPassword,
      },
      url: "/v1/auth/login",
    });
    expect(sameDeviceLogin.statusCode).toBe(200);
    const currentPair = sameDeviceLogin.json<TokenResponse>();

    const replacedAccess = await app.inject({
      headers: {
        authorization: `Bearer ${replacementPair.accessToken}`,
      },
      method: "GET",
      url: "/v1/auth/sessions",
    });
    expect(replacedAccess.statusCode).toBe(401);

    const logout = await app.inject({
      headers: {
        authorization: `Bearer ${currentPair.accessToken}`,
      },
      method: "POST",
      payload: { allDevices: true },
      url: "/v1/auth/logout",
    });
    expect(logout.statusCode).toBe(204);

    const loggedOutAccess = await app.inject({
      headers: {
        authorization: `Bearer ${currentPair.accessToken}`,
      },
      method: "GET",
      url: "/v1/auth/sessions",
    });
    expect(loggedOutAccess.statusCode).toBe(401);
  }, 30_000);
});
