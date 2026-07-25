import { createHash } from "node:crypto";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { AppleBillingVerifier } from "./apple/verifier.js";
import { BillingRepository } from "./repository.js";
import type {
  BillingProduct,
  EntitlementSnapshot,
  EntitlementStatus,
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
}>;

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
      if (transaction.expiresAt === undefined) {
        throw new AppError({
          code: "APPLE_SUBSCRIPTION_EXPIRY_REQUIRED",
          message: "The verified transaction is not a subscription.",
          statusCode: 400,
        });
      }
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
  };
}
