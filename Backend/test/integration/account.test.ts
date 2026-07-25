import { randomBytes } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { registerAccountRoutes } from "../../src/modules/account/routes.js";
import { createAccountService } from "../../src/modules/account/service.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { createCredentialSealer } from "../../src/modules/auth/apple/credential-crypto.js";
import { AuthRepository } from "../../src/modules/auth/repository.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import type { JobWorker } from "../../src/modules/jobs/worker.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

type DeletionResponse = Readonly<{
  cancellationToken: string | null;
  purgeAt: string;
  requestId: string;
  status: "scheduled";
}>;

describe.runIf(runIntegrationTests)("account data governance", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let jobWorker: JobWorker;
  let accessToken: string;
  let userId: string;
  let transactionId: string;
  let originalTransactionId: string;
  const deletionRequestIds: string[] = [];
  const email = `account-${newEntityId()}@example.com`;
  const password = "Correct Horse Account 1!";
  const verificationTokens = new Map<string, string>();
  const revokedAppleTokens: string[] = [];

  beforeAll(async () => {
    const config = loadConfig({
      ACCOUNT_DELETION_GRACE_DAYS: "1",
      APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64: randomBytes(32).toString("base64"),
      APPLE_CREDENTIAL_KEY_VERSION: "account-test-v1",
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
    const credentialSealer = createCredentialSealer(config);
    const accountService = createAccountService(config, dependencies.database, {
      appleTokenRevoker: {
        revokeRefreshToken: (clientId, refreshToken) => {
          revokedAppleTokens.push(`${clientId}:${refreshToken}`);
          return Promise.resolve();
        },
      },
      credentialSealer,
    });
    jobWorker = createTestJobWorker(config, dependencies.database, notifier, {
      processAccountPurge: accountService.processDeletion,
    });
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerAccountRoutes(app, authService, accountService);

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
          deviceId: "account-test-device",
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

    const authRepository = new AuthRepository(dependencies.database);
    const linked = await authRepository.linkAppleIdentity({
      email: "account-apple@example.com",
      emailVerified: true,
      subject: `account-apple-${newEntityId()}`,
      userId,
    });
    if (linked.status !== "linked") {
      throw new Error("Apple identity fixture could not be linked");
    }
    await authRepository.saveProviderCredential(
      linked.identityId,
      "com.tiantian.lingotrip",
      credentialSealer.seal("account-apple-refresh-token"),
    );

    transactionId = `account-transaction-${newEntityId()}`;
    originalTransactionId = `account-original-${newEntityId()}`;
    await dependencies.database.sql`
      insert into app.billing_transactions (
        id,
        provider,
        environment,
        transaction_id,
        original_transaction_id,
        user_id,
        app_account_token,
        product_id,
        plan_id,
        purchased_at,
        signed_at,
        raw_payload
      )
      values (
        ${newEntityId()},
        'apple',
        'test',
        ${transactionId},
        ${originalTransactionId},
        ${userId},
        ${userId},
        'com.tiantian.lingotrip.plus.monthly',
        'plus',
        now(),
        now(),
        '{"private":"must be redacted"}'::jsonb
      )
    `;
    await dependencies.database.sql`
      insert into app.subscriptions (
        id,
        provider,
        environment,
        original_transaction_id,
        user_id,
        product_id,
        plan_id,
        latest_transaction_id,
        status,
        provider_event_at
      )
      values (
        ${newEntityId()},
        'apple',
        'test',
        ${originalTransactionId},
        ${userId},
        'com.tiantian.lingotrip.plus.monthly',
        'plus',
        ${transactionId},
        'active',
        now()
      )
    `;
  });

  afterAll(async () => {
    await app.close();
    if (deletionRequestIds.length > 0) {
      await dependencies.database.sql`
        delete from app.jobs
        where unique_key in ${dependencies.database.sql(
          deletionRequestIds.map((id) => `account-deletion:${id}`),
        )}
      `;
      await dependencies.database.sql`
        delete from app.account_deletion_requests
        where id in ${dependencies.database.sql(deletionRequestIds)}
      `;
    }
    await dependencies.database.sql`
      delete from app.subscriptions
      where provider = 'apple'
        and environment = 'test'
        and original_transaction_id = ${originalTransactionId}
    `;
    await dependencies.database.sql`
      delete from app.billing_transactions
      where provider = 'apple'
        and environment = 'test'
        and transaction_id = ${transactionId}
    `;
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

  it("exports portable data, supports grace cancellation, and purges immediately", async () => {
    const authorization = { authorization: `Bearer ${accessToken}` };
    const exported = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/v1/account/export",
    });
    expect(exported.statusCode).toBe(200);
    expect(exported.headers["cache-control"]).toBe("no-store");
    expect(exported.headers["content-disposition"]).toContain("attachment;");
    expect(exported.json<{ account: { userId: string } }>().account.userId).toBe(
      userId,
    );
    expect(exported.body).toContain(email);
    expect(exported.body).toContain(transactionId);
    expect(exported.body).not.toContain(password);
    expect(exported.body).not.toContain("passwordHash");
    expect(exported.body).not.toContain("rawPayload");

    const graceResponse = await app.inject({
      headers: authorization,
      method: "DELETE",
      payload: {
        confirmation: "DELETE",
        mode: "grace_period",
      },
      url: "/v1/account",
    });
    expect(graceResponse.statusCode).toBe(202);
    const grace = graceResponse.json<DeletionResponse>();
    deletionRequestIds.push(grace.requestId);
    expect(grace.cancellationToken).toBeTypeOf("string");
    expect(new Date(grace.purgeAt).getTime()).toBeGreaterThan(Date.now());

    const revokedAccess = await app.inject({
      headers: authorization,
      method: "GET",
      url: "/v1/account/export",
    });
    expect(revokedAccess.statusCode).toBe(401);

    const cancellation = await app.inject({
      method: "POST",
      payload: { token: grace.cancellationToken },
      url: "/v1/account/deletion/cancel",
    });
    expect(cancellation.statusCode).toBe(204);
    const cancellationReplay = await app.inject({
      method: "POST",
      payload: { token: grace.cancellationToken },
      url: "/v1/account/deletion/cancel",
    });
    expect(cancellationReplay.statusCode).toBe(400);

    const login = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "account-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    expect(login.statusCode).toBe(200);
    const current = login.json<TokenResponse>();

    const immediateResponse = await app.inject({
      headers: {
        authorization: `Bearer ${current.accessToken}`,
      },
      method: "DELETE",
      payload: {
        confirmation: "DELETE",
        mode: "immediate",
      },
      url: "/v1/account",
    });
    expect(immediateResponse.statusCode).toBe(202);
    const immediate = immediateResponse.json<DeletionResponse>();
    deletionRequestIds.push(immediate.requestId);
    expect(immediate.cancellationToken).toBeNull();
    expect(await jobWorker.runOnce()).toBe("succeeded");
    expect(revokedAppleTokens).toEqual([
      "com.tiantian.lingotrip:account-apple-refresh-token",
    ]);

    const deletedLogin = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "account-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    expect(deletedLogin.statusCode).toBe(401);

    const [deletion] = await dependencies.database.sql<
      { status: string; user_id: string | null }[]
    >`
      select status, user_id::text
      from app.account_deletion_requests
      where id = ${immediate.requestId}
    `;
    expect(deletion).toEqual({ status: "completed", user_id: null });
    const [transaction] = await dependencies.database.sql<
      {
        app_account_token: string | null;
        raw_payload: { redacted: boolean };
        user_id: string | null;
      }[]
    >`
      select app_account_token::text, raw_payload, user_id::text
      from app.billing_transactions
      where provider = 'apple'
        and environment = 'test'
        and transaction_id = ${transactionId}
    `;
    expect(transaction).toEqual({
      app_account_token: null,
      raw_payload: { redacted: true },
      user_id: null,
    });
    const [subscription] = await dependencies.database.sql<
      { user_id: string | null }[]
    >`
      select user_id::text
      from app.subscriptions
      where provider = 'apple'
        and environment = 'test'
        and original_transaction_id = ${originalTransactionId}
    `;
    expect(subscription?.user_id).toBeNull();
  }, 30_000);
});
