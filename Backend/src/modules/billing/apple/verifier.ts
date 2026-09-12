import {
  Environment,
  SignedDataVerifier,
  type JWSRenewalInfoDecodedPayload,
  type JWSTransactionDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from "@apple/app-store-server-library";
import { createHash } from "node:crypto";
import type { RuntimeConfig } from "../../../config/env.js";
import { AppError } from "../../../shared/errors.js";
import type {
  StoreEnvironment,
  VerifiedRenewalInfo,
  VerifiedStoreNotification,
  VerifiedStoreTransaction,
} from "../types.js";

type VerifierEntry = Readonly<{
  environment: StoreEnvironment;
  verifier: SignedDataVerifier;
}>;

function requiredString(value: string | undefined, field: string): string {
  if (value === undefined || value.length === 0) {
    throw new AppError({
      code: "APPLE_TRANSACTION_INCOMPLETE",
      message: `The verified Apple payload is missing ${field}.`,
      statusCode: 400,
    });
  }
  return value;
}

function requiredDate(value: number | undefined, field: string): Date {
  if (value === undefined || !Number.isFinite(value)) {
    throw new AppError({
      code: "APPLE_TRANSACTION_INCOMPLETE",
      message: `The verified Apple payload is missing ${field}.`,
      statusCode: 400,
    });
  }
  return new Date(value);
}

function mapTransaction(
  payload: JWSTransactionDecodedPayload,
  environment: StoreEnvironment,
): VerifiedStoreTransaction {
  return {
    ...(payload.appAccountToken === undefined
      ? {}
      : { appAccountToken: payload.appAccountToken }),
    environment,
    ...(payload.expiresDate === undefined
      ? {}
      : { expiresAt: new Date(payload.expiresDate) }),
    originalTransactionId: requiredString(
      payload.originalTransactionId,
      "originalTransactionId",
    ),
    ...(payload.inAppOwnershipType === undefined
      ? {}
      : { ownershipType: payload.inAppOwnershipType }),
    productId: requiredString(payload.productId, "productId"),
    ...(payload.price === undefined ? {} : { price: payload.price }),
    purchasedAt: requiredDate(payload.purchaseDate, "purchaseDate"),
    rawPayload: payload,
    ...(payload.revocationDate === undefined
      ? {}
      : { revokedAt: new Date(payload.revocationDate) }),
    signedAt: requiredDate(payload.signedDate, "signedDate"),
    transactionId: requiredString(payload.transactionId, "transactionId"),
  };
}

function mapRenewal(payload: JWSRenewalInfoDecodedPayload): VerifiedRenewalInfo {
  return {
    ...(payload.appAccountToken === undefined
      ? {}
      : { appAccountToken: payload.appAccountToken }),
    ...(payload.autoRenewStatus === undefined
      ? {}
      : { autoRenewEnabled: payload.autoRenewStatus === 1 }),
    ...(payload.gracePeriodExpiresDate === undefined
      ? {}
      : { gracePeriodExpiresAt: new Date(payload.gracePeriodExpiresDate) }),
    ...(payload.originalTransactionId === undefined
      ? {}
      : { originalTransactionId: payload.originalTransactionId }),
    ...(payload.productId === undefined ? {} : { productId: payload.productId }),
    rawPayload: payload,
    ...(payload.signedDate === undefined
      ? {}
      : { signedAt: new Date(payload.signedDate) }),
  };
}

export type AppleBillingVerifier = Readonly<{
  verifyNotification: (signedPayload: string) => Promise<VerifiedStoreNotification>;
  verifyRenewal: (
    signedRenewalInfo: string,
    expectedEnvironment?: StoreEnvironment,
  ) => Promise<VerifiedRenewalInfo>;
  verifyTransaction: (
    signedTransaction: string,
    expectedEnvironment?: StoreEnvironment,
  ) => Promise<VerifiedStoreTransaction>;
}>;

export function createAppleBillingVerifier(
  config: RuntimeConfig,
): AppleBillingVerifier {
  if (!config.appleBillingEnabled || config.appleBillingAppAppleId === undefined) {
    throw new Error("Apple billing verifier was created while billing is disabled");
  }

  const verifiers: readonly VerifierEntry[] = [
    {
      environment: "production",
      verifier: new SignedDataVerifier(
        [...config.appleBillingRootCaCertificates],
        config.appleBillingEnableOnlineChecks,
        Environment.PRODUCTION,
        config.appleBillingBundleId,
        config.appleBillingAppAppleId,
      ),
    },
    {
      environment: "sandbox",
      verifier: new SignedDataVerifier(
        [...config.appleBillingRootCaCertificates],
        config.appleBillingEnableOnlineChecks,
        Environment.SANDBOX,
        config.appleBillingBundleId,
      ),
    },
  ];

  const verifyOuter = async (
    signedPayload: string,
  ): Promise<
    Readonly<{
      entry: VerifierEntry;
      payload: ResponseBodyV2DecodedPayload;
    }>
  > => {
    let lastError: unknown;
    for (const entry of verifiers) {
      try {
        return {
          entry,
          payload: await entry.verifier.verifyAndDecodeNotification(signedPayload),
        };
      } catch (error) {
        lastError = error;
      }
    }
    throw new AppError({
      cause: lastError,
      code: "APPLE_JWS_VERIFICATION_FAILED",
      message: "The App Store notification signature is invalid.",
      statusCode: 400,
    });
  };

  const verifyTransaction = async (
    signedTransaction: string,
    expectedEnvironment?: StoreEnvironment,
  ): Promise<VerifiedStoreTransaction> => {
    let lastError: unknown;
    for (const entry of verifiers.filter(
      (candidate) =>
        expectedEnvironment === undefined ||
        candidate.environment === expectedEnvironment,
    )) {
      try {
        const payload =
          await entry.verifier.verifyAndDecodeTransaction(signedTransaction);
        return mapTransaction(payload, entry.environment);
      } catch (error) {
        lastError = error;
      }
    }
    throw new AppError({
      cause: lastError,
      code: "APPLE_JWS_VERIFICATION_FAILED",
      message: "The App Store transaction signature is invalid.",
      statusCode: 400,
    });
  };

  const verifyRenewal = async (
    signedRenewalInfo: string,
    expectedEnvironment?: StoreEnvironment,
  ): Promise<VerifiedRenewalInfo> => {
    let lastError: unknown;
    for (const entry of verifiers.filter(
      (candidate) =>
        expectedEnvironment === undefined ||
        candidate.environment === expectedEnvironment,
    )) {
      try {
        return mapRenewal(
          await entry.verifier.verifyAndDecodeRenewalInfo(signedRenewalInfo),
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw new AppError({
      cause: lastError,
      code: "APPLE_JWS_VERIFICATION_FAILED",
      message: "The App Store renewal signature is invalid.",
      statusCode: 400,
    });
  };

  return {
    verifyNotification: async (signedPayload) => {
      const { entry, payload } = await verifyOuter(signedPayload);
      const transaction =
        payload.data?.signedTransactionInfo === undefined
          ? undefined
          : mapTransaction(
              await entry.verifier.verifyAndDecodeTransaction(
                payload.data.signedTransactionInfo,
              ),
              entry.environment,
            );
      const renewal =
        payload.data?.signedRenewalInfo === undefined
          ? undefined
          : mapRenewal(
              await entry.verifier.verifyAndDecodeRenewalInfo(
                payload.data.signedRenewalInfo,
              ),
            );
      return {
        decodedPayload: payload,
        environment: entry.environment,
        eventId: requiredString(payload.notificationUUID, "notificationUUID"),
        eventType: requiredString(payload.notificationType, "notificationType"),
        payloadHash: createHash("sha256").update(signedPayload).digest("hex"),
        ...(payload.data?.status === undefined
          ? {}
          : { providerStatus: payload.data.status }),
        ...(renewal === undefined ? {} : { renewal }),
        signedAt: requiredDate(payload.signedDate, "signedDate"),
        ...(payload.subtype === undefined ? {} : { subtype: payload.subtype }),
        ...(transaction === undefined ? {} : { transaction }),
      };
    },
    verifyRenewal,
    verifyTransaction,
  };
}
