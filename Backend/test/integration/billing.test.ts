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
import type { AppleBillingVerifier } from "../../src/modules/billing/apple/verifier.js";
import type { AppleBillingStatusClient } from "../../src/modules/billing/apple/server-api-client.js";
import { registerBillingRoutes } from "../../src/modules/billing/routes.js";
import { createBillingService } from "../../src/modules/billing/service.js";
import type {
  EntitlementSnapshot,
  VerifiedSubscriptionStatus,
  VerifiedStoreNotification,
  VerifiedStoreTransaction,
} from "../../src/modules/billing/types.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("billing entitlements", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  let verifiedTransaction: VerifiedStoreTransaction;
  let verifiedNotification: VerifiedStoreNotification;
  let reconciliationStatuses: readonly VerifiedSubscriptionStatus[] = [];
  let billingService: ReturnType<typeof createBillingService>;
  const verificationTokens = new Map<string, string>();
  const email = `billing-${newEntityId()}@example.com`;
  const password = "Correct Horse Billing 1!";
  const baseSignedAt = new Date("2030-01-01T00:00:00.000Z");
  const signedTransaction = "signed-transaction-payload-for-integration-test";
  const signedNotification = "signed-notification-payload-for-integration-test";

  const headers = (idempotencyKey?: string) => ({
    authorization: `Bearer ${accessToken}`,
    ...(idempotencyKey === undefined ? {} : { "idempotency-key": idempotencyKey }),
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
    const fakeVerifier: AppleBillingVerifier = {
      verifyNotification: () => Promise.resolve(verifiedNotification),
      verifyRenewal: () => Promise.resolve({ rawPayload: {} }),
      verifyTransaction: () => Promise.resolve(verifiedTransaction),
    };
    const fakeStatusClient: AppleBillingStatusClient = {
      statuses: () => Promise.resolve(reconciliationStatuses),
    };
    billingService = createBillingService(
      dependencies.database,
      fakeVerifier,
      fakeStatusClient,
    );
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerBillingRoutes(app, authService, billingService, {
      appleBillingEnabled: true,
      enableDebugRoutes: true,
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
          deviceId: "billing-test-device",
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

    verifiedTransaction = {
      appAccountToken: userId,
      environment: "sandbox",
      expiresAt: new Date("2030-02-01T00:00:00.000Z"),
      originalTransactionId: "billing-original-1",
      ownershipType: "PURCHASED",
      productId: "com.tiantian.lingotrip.plus.monthly",
      purchasedAt: baseSignedAt,
      rawPayload: { transactionId: "billing-transaction-1" },
      signedAt: baseSignedAt,
      transactionId: "billing-transaction-1",
    };
    verifiedNotification = {
      decodedPayload: { notificationType: "REFUND" },
      environment: "sandbox",
      eventId: newEntityId(),
      eventType: "REFUND",
      payloadHash: "refund-payload-hash",
      providerStatus: 5,
      signedAt: new Date("2030-01-02T00:00:00.000Z"),
      transaction: {
        ...verifiedTransaction,
        rawPayload: {
          revocationDate: "2030-01-02T00:00:00.000Z",
          transactionId: "billing-transaction-1",
        },
        revokedAt: new Date("2030-01-02T00:00:00.000Z"),
        signedAt: new Date("2030-01-02T00:00:00.000Z"),
      },
    };
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
      delete from app.billing_provider_events
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.subscriptions
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.billing_transactions
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.users
      where id = ${userId}
    `;
    await dependencies.close();
  });

  it("derives server authority from verified transactions and notifications", async () => {
    const products = await app.inject({
      method: "GET",
      url: "/v1/billing/products",
    });
    expect(products.statusCode).toBe(200);
    expect(products.json<{ products: readonly unknown[] }>().products).toHaveLength(4);

    const initial = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/billing/entitlements",
    });
    expect(initial.json<EntitlementSnapshot>().tier).toBe("free");

    const commandId = newEntityId();
    const purchase = await app.inject({
      headers: headers(commandId),
      method: "POST",
      payload: { signedTransaction },
      url: "/v1/billing/apple/transactions",
    });
    expect(purchase.statusCode).toBe(200);
    expect(purchase.json<EntitlementSnapshot>()).toMatchObject({
      tier: "plus",
    });

    const retry = await app.inject({
      headers: headers(commandId),
      method: "POST",
      payload: { signedTransaction },
      url: "/v1/billing/apple/transactions",
    });
    expect(retry.json<EntitlementSnapshot>()).toEqual(purchase.json());

    const conflictingRetry = await app.inject({
      headers: headers(commandId),
      method: "POST",
      payload: {
        signedTransaction: "different-signed-transaction-payload-for-integration-test",
      },
      url: "/v1/billing/apple/transactions",
    });
    expect(conflictingRetry.statusCode).toBe(409);
    expect(conflictingRetry.json<{ code: string }>().code).toBe(
      "IDEMPOTENCY_KEY_CONFLICT",
    );

    const notification = await app.inject({
      method: "POST",
      payload: { signedPayload: signedNotification },
      url: "/v1/billing/apple/notifications",
    });
    expect(notification.statusCode).toBe(204);

    const notificationRetry = await app.inject({
      method: "POST",
      payload: { signedPayload: signedNotification },
      url: "/v1/billing/apple/notifications",
    });
    expect(notificationRetry.statusCode).toBe(204);

    verifiedNotification = {
      decodedPayload: { notificationType: "DID_RENEW" },
      environment: "sandbox",
      eventId: newEntityId(),
      eventType: "DID_RENEW",
      payloadHash: "stale-renewal-payload-hash",
      providerStatus: 1,
      signedAt: new Date("2029-12-31T00:00:00.000Z"),
      transaction: {
        ...verifiedTransaction,
        appAccountToken: userId,
        signedAt: new Date("2029-12-31T00:00:00.000Z"),
      },
    };
    const staleNotification = await app.inject({
      method: "POST",
      payload: { signedPayload: signedNotification },
      url: "/v1/billing/apple/notifications",
    });
    expect(staleNotification.statusCode).toBe(204);

    const revoked = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/billing/entitlements",
    });
    expect(revoked.json<EntitlementSnapshot>().tier).toBe("free");

    reconciliationStatuses = [
      {
        providerStatus: 1,
        transaction: {
          ...verifiedTransaction,
          appAccountToken: userId,
          rawPayload: { source: "status-api" },
          signedAt: new Date("2030-01-03T00:00:00.000Z"),
        },
      },
    ];
    const reconciliation = await billingService.reconcileAppleSubscriptions();
    expect(reconciliation).toEqual({
      claimed: 1,
      failed: 0,
      succeeded: 1,
    });
    const reconciled = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/billing/entitlements",
    });
    expect(reconciled.json<EntitlementSnapshot>().tier).toBe("plus");

    const [counts] = await dependencies.database.sql<
      {
        event_count: number;
        last_reconciled: boolean;
        reconciliation_attempts: number;
        reconciliation_error: string | null;
        sync_count: number;
        transaction_count: number;
      }[]
    >`
      select
        (
          select count(*)::int
          from app.billing_transactions
          where user_id = ${userId}
        ) as transaction_count,
        (
          select count(*)::int
          from app.billing_provider_events
          where user_id = ${userId}
        ) as event_count,
        (
          select count(*)::int
          from app.sync_changes
          where user_id = ${userId}
            and event_type = 'billing.entitlementsUpdated'
        ) as sync_count,
        (
          select last_reconciled_at is not null
          from app.subscriptions
          where user_id = ${userId}
        ) as last_reconciled,
        (
          select reconciliation_attempts
          from app.subscriptions
          where user_id = ${userId}
        ) as reconciliation_attempts,
        (
          select reconciliation_error
          from app.subscriptions
          where user_id = ${userId}
        ) as reconciliation_error
    `;
    expect(counts).toEqual({
      event_count: 2,
      last_reconciled: true,
      reconciliation_attempts: 0,
      reconciliation_error: null,
      sync_count: 3,
      transaction_count: 1,
    });

    await dependencies.database.sql`
      update app.subscriptions
      set reconcile_after = now()
      where user_id = ${userId}
    `;
    reconciliationStatuses = [];
    expect(await billingService.reconcileAppleSubscriptions()).toEqual({
      claimed: 1,
      failed: 1,
      succeeded: 0,
    });
    const [failedReconciliation] = await dependencies.database.sql<
      {
        reconciliation_attempts: number;
        reconciliation_error: string | null;
        retry_scheduled: boolean;
      }[]
    >`
      select
        reconciliation_attempts,
        reconciliation_error,
        reconcile_after > now() as retry_scheduled
      from app.subscriptions
      where user_id = ${userId}
    `;
    expect(failedReconciliation).toEqual({
      reconciliation_attempts: 1,
      reconciliation_error: "APPLE_SUBSCRIPTION_STATUS_MISSING",
      retry_scheduled: true,
    });
  }, 30_000);

  it("rejects a verified transaction bound to another app account", async () => {
    verifiedTransaction = {
      ...verifiedTransaction,
      appAccountToken: newEntityId(),
      transactionId: "billing-transaction-mismatch",
    };
    const response = await app.inject({
      headers: headers(newEntityId()),
      method: "POST",
      payload: { signedTransaction },
      url: "/v1/billing/apple/transactions",
    });
    expect(response.statusCode).toBe(409);
    expect(response.json<{ code: string }>().code).toBe("APP_ACCOUNT_TOKEN_MISMATCH");
  });
});
