import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { registerAppleAuthRoutes } from "../../src/modules/auth/apple/routes.js";
import { createAppleAuthService } from "../../src/modules/auth/apple/service.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { newEntityId } from "../../src/shared/id.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  refreshToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("Sign in with Apple", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let userId: string | undefined;
  const challengeId = newEntityId();
  const nonce = "one-time-apple-nonce";
  let challengeAvailable = true;

  beforeAll(async () => {
    const config = loadConfig({ NODE_ENV: "test" });
    dependencies = createRuntimeDependencies(config);
    await runMigrations(dependencies.database);
    await dependencies.start();
    const authService = await createAuthService(config, dependencies.database);
    const appleService = await createAppleAuthService(
      config,
      dependencies.database,
      dependencies.redis,
      authService,
      {
        challengeStore: {
          consume: () => {
            if (!challengeAvailable) {
              return Promise.resolve(null);
            }
            challengeAvailable = false;
            return Promise.resolve(nonce);
          },
          create: () =>
            Promise.resolve({
              challengeId,
              expiresIn: 300,
              nonce,
            }),
        },
        codeExchanger: {
          exchange: () =>
            Promise.resolve({
              idToken: "exchanged-id-token",
              refreshToken: "apple-refresh-token",
            }),
        },
        credentialSealer: {
          open: () => "apple-refresh-token",
          seal: () => ({
            ciphertext: Buffer.from("ciphertext"),
            keyVersion: "test-v1",
            nonce: Buffer.alloc(12, 1),
            tag: Buffer.alloc(16, 2),
          }),
        },
        identityVerifier: {
          verify: (_token, expectedNonce) => {
            if (expectedNonce !== undefined && expectedNonce !== nonce) {
              return Promise.reject(new Error("nonce mismatch"));
            }
            return Promise.resolve({
              audience: "com.tiantian.lingotrip",
              email: "apple-user@example.com",
              emailVerified: true,
              isPrivateEmail: false,
              nonce,
              realUserStatus: 2,
              subject: `apple-subject-${challengeId}`,
            });
          },
        },
      },
    );
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerAppleAuthRoutes(app, appleService, authService);
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

  it("creates a federated account, stores a sealed refresh token, and rejects replay", async () => {
    const challenge = await app.inject({
      method: "POST",
      url: "/v1/auth/apple/challenge",
    });
    expect(challenge.statusCode).toBe(200);
    expect(challenge.json()).toEqual({
      challengeId,
      expiresIn: 300,
      nonce,
    });

    const login = await app.inject({
      method: "POST",
      payload: {
        authorizationCode: "single-use-code",
        challengeId,
        device: {
          deviceId: "apple-test-device",
          platform: "ios",
        },
        identityToken: "apple-id-token",
      },
      url: "/v1/auth/apple/login",
    });
    expect(login.statusCode).toBe(200);
    const pair = login.json<TokenResponse>();
    userId = pair.userId;

    const [credential] = await dependencies.database.sql<
      {
        ciphertext: Buffer;
        key_version: string;
        provider_client_id: string;
      }[]
    >`
      select c.ciphertext, c.key_version, c.provider_client_id
      from app.identity_provider_credentials c
      join app.user_identities i on i.id = c.identity_id
      where i.user_id = ${pair.userId}
        and i.provider = 'apple'
    `;
    expect(credential?.key_version).toBe("test-v1");
    expect(credential?.provider_client_id).toBe("com.tiantian.lingotrip");
    expect(credential?.ciphertext).toEqual(Buffer.from("ciphertext"));

    const sessions = await app.inject({
      headers: {
        authorization: `Bearer ${pair.accessToken}`,
      },
      method: "GET",
      url: "/v1/auth/sessions",
    });
    expect(sessions.statusCode).toBe(200);

    const replay = await app.inject({
      method: "POST",
      payload: {
        authorizationCode: "single-use-code",
        challengeId,
        device: {
          deviceId: "apple-test-device",
          platform: "ios",
        },
        identityToken: "apple-id-token",
      },
      url: "/v1/auth/apple/login",
    });
    expect(replay.statusCode).toBe(401);
    expect(replay.json<{ code: string }>().code).toBe("APPLE_CHALLENGE_INVALID");
  });
});
