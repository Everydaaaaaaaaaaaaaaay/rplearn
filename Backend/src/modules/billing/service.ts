import { createHash } from "node:crypto";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { AppleBillingStatusClient } from "./apple/server-api-client.js";
import type { AppleBillingVerifier } from "./apple/verifier.js";
import { BillingRepository } from "./repository.js";
import type {
  BillingProduct,
  EntitlementSnapshot,
  EntitlementStatus,
  SubscriptionReconciliationClaim,
  SubscriptionReconciliationResult,
  SubscriptionTier,
  VerifiedRenewalInfo,
  VerifiedStoreNotification,
  VerifiedStoreTransaction,
} from "./types.js";

const uuidSchema = z.uuid();

export function entitlementStatusForApple(
  transaction: VerifiedStoreTransaction,
  renewal: VerifiedRenewalInfo | undefined,
  providerStatus: number | undefined,
  now: Date = new Date(),
): EntitlementStatus {
  if (transaction.revokedAt !== undefined || providerStatus === 5) {
    return "revoked";
  }
  switch (providerStatus) {
    case 1:
      return "active";
    case 2:
      return "expired";
    case 3:
      return "billing_retry";
    case 4:
      return "grace";
  }
  if (
    renewal?.gracePeriodExpiresAt !== undefined &&
    renewal.gracePeriodExpiresAt > now
  ) {
    return "grace";
  }
  return transaction.expiresAt !== undefined && transaction.expiresAt > now
    ? "active"
    : "expired";
}

export type BillingService = Readonly<{
  getEntitlements: (userId: string) => Promise<EntitlementSnapshot>;
  grantDebugEntitlement: (
    userId: string,
    commandId: string,
    tier: Exclude<SubscriptionTier, "free">,
    durationDays: number,
  ) => Promise<EntitlementSnapshot>;
  ingestAppleNotification: (signedPayload: string) => Promise<void>;
  ingestAppleTransaction: (
    userId: string,
    commandId: string,
    signedTransaction: string,
  ) => Promise<EntitlementSnapshot>;
  listProducts: () => Promise<readonly BillingProduct[]>;
  reconcileAppleSubscriptions: (
    limit?: number,
  ) => Promise<SubscriptionReconciliationResult>;
}>;

export type BillingReconciliationPolicy = Readonly<{
  activeHours: number;
  batchSize: number;
  inactiveHours: number;
  retryMinutes: number;
}>;

const DEFAULT_RECONCILIATION_POLICY: BillingReconciliationPolicy = {
  activeHours: 6,
  batchSize: 100,
  inactiveHours: 24,
  retryMinutes: 15,
};

async function resolveNotificationUser(
  repository: BillingRepository,
  notification: VerifiedStoreNotification,
): Promise<string | undefined> {
  const transaction = notification.transaction;
  if (transaction === undefined) {
    return undefined;
  }
  const token = transaction.appAccountToken ?? notification.renewal?.appAccountToken;
  if (token !== undefined && uuidSchema.safeParse(token).success) {
    return (await repository.userExists(token)) ? token : undefined;
  }
  return repository.userForOriginalTransaction(
    transaction.environment,
    transaction.originalTransactionId,
  );
}

export function createBillingService(
  database: DatabaseResource,
  appleVerifier?: AppleBillingVerifier,
  appleStatusClient?: AppleBillingStatusClient,
  reconciliationPolicy: BillingReconciliationPolicy = DEFAULT_RECONCILIATION_POLICY,
): BillingService {
  const repository = new BillingRepository(database);

  const verifier = (): AppleBillingVerifier => {
    if (appleVerifier === undefined) {
      throw new AppError({
        code: "APPLE_BILLING_NOT_CONFIGURED",
        message: "Apple billing verification is not configured.",
        statusCode: 503,
      });
    }
    return appleVerifier;
  };

  const reconcileOne = async (
    claim: SubscriptionReconciliationClaim,
  ): Promise<boolean> => {
    const now = new Date();
    try {
      if (appleStatusClient === undefined) {
        throw new AppError({
          code: "APPLE_BILLING_NOT_CONFIGURED",
          message: "Apple billing reconciliation is not configured.",
          statusCode: 503,
        });
      }
      const statuses = await appleStatusClient.statuses(
        claim.environment,
        claim.latestTransactionId,
      );
      const latest = statuses
        .filter(
          (candidate) =>
            candidate.transaction.originalTransactionId === claim.originalTransactionId,
        )
        .sort(
          (left, right) =>
            right.transaction.signedAt.getTime() - left.transaction.signedAt.getTime(),
        )[0];
      if (latest === undefined) {
        throw new AppError({
          code: "APPLE_SUBSCRIPTION_STATUS_MISSING",
          message: "The App Store response did not include the expected subscription.",
          statusCode: 502,
        });
      }
      const appAccountToken =
        latest.transaction.appAccountToken ?? latest.renewal?.appAccountToken;
      if (
        appAccountToken !== undefined &&
        appAccountToken.toLowerCase() !== claim.userId.toLowerCase()
      ) {
        throw new AppError({
          code: "APP_ACCOUNT_TOKEN_MISMATCH",
          message: "The subscription belongs to another app account.",
          statusCode: 409,
        });
      }
      const status = entitlementStatusForApple(
        latest.transaction,
        latest.renewal,
        latest.providerStatus,
        now,
      );
      const hours =
        status === "active"
          ? reconciliationPolicy.activeHours
          : status === "grace" || status === "billing_retry"
            ? 1
            : reconciliationPolicy.inactiveHours;
      return await repository.completeSubscriptionReconciliation(
        claim,
        latest,
        status,
        now,
        new Date(now.getTime() + hours * 60 * 60 * 1000),
      );
    } catch (error) {
      const errorCode =
        error instanceof AppError
          ? error.code
          : "APPLE_SUBSCRIPTION_RECONCILIATION_FAILED";
      const retryMinutes = Math.min(
        reconciliationPolicy.inactiveHours * 60,
        reconciliationPolicy.retryMinutes *
          2 ** Math.min(Math.max(0, claim.attempts - 1), 6),
      );
      await repository.failSubscriptionReconciliation(
        claim,
        errorCode,
        new Date(now.getTime() + retryMinutes * 60 * 1000),
      );
      return false;
    }
  };

  return {
    getEntitlements: (userId) => repository.entitlements(userId),
    grantDebugEntitlement: (userId, commandId, tier, durationDays) =>
      repository.grantDebugEntitlement(userId, commandId, tier, durationDays),
    ingestAppleNotification: async (signedPayload) => {
      const notification = await verifier().verifyNotification(signedPayload);
      const userId = await resolveNotificationUser(repository, notification);
      const status =
        notification.transaction === undefined
          ? undefined
          : entitlementStatusForApple(
              notification.transaction,
              notification.renewal,
              notification.providerStatus,
            );
      await repository.ingestNotification(notification, userId, status);
    },
    ingestAppleTransaction: async (userId, commandId, signedTransaction) => {
      const transaction = await verifier().verifyTransaction(signedTransaction);
      if (transaction.appAccountToken !== undefined) {
        if (transaction.appAccountToken.toLowerCase() !== userId.toLowerCase()) {
          throw new AppError({
            code: "APP_ACCOUNT_TOKEN_MISMATCH",
            message: "The transaction belongs to another app account.",
            statusCode: 409,
          });
        }
      } else {
        const existingUser = await repository.userForOriginalTransaction(
          transaction.environment,
          transaction.originalTransactionId,
        );
        if (existingUser !== userId) {
          throw new AppError({
            code: "APP_ACCOUNT_TOKEN_REQUIRED",
            message:
              "New subscriptions must include the authenticated user ID as appAccountToken.",
            statusCode: 409,
          });
        }
      }
      return repository.ingestTransaction(
        userId,
        commandId,
        createHash("sha256").update(signedTransaction).digest("hex"),
        transaction,
        entitlementStatusForApple(transaction, undefined, undefined),
      );
    },
    listProducts: () => repository.listProducts(),
    reconcileAppleSubscriptions: async (requestedLimit) => {
      const limit = Math.max(
        1,
        Math.min(500, requestedLimit ?? reconciliationPolicy.batchSize),
      );
      const startedAt = new Date();
      const claims = await repository.claimSubscriptionsForReconciliation(
        limit,
        startedAt,
        new Date(startedAt.getTime() + 5 * 60 * 1000),
      );
      let succeeded = 0;
      const concurrency = 5;
      for (let offset = 0; offset < claims.length; offset += concurrency) {
        const results = await Promise.all(
          claims.slice(offset, offset + concurrency).map(reconcileOne),
        );
        succeeded += results.filter(Boolean).length;
      }
      return {
        claimed: claims.length,
        failed: claims.length - succeeded,
        succeeded,
      };
    },
  };
}
