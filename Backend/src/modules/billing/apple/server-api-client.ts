import {
  AppStoreServerAPIClient,
  Environment,
  type StatusResponse,
} from "@apple/app-store-server-library";
import type { RuntimeConfig } from "../../../config/env.js";
import { AppError } from "../../../shared/errors.js";
import type { StoreEnvironment, VerifiedSubscriptionStatus } from "../types.js";
import type { AppleBillingVerifier } from "./verifier.js";

type ServerApi = Pick<AppStoreServerAPIClient, "getAllSubscriptionStatuses">;

export type AppleBillingStatusClient = Readonly<{
  statuses: (
    environment: Exclude<StoreEnvironment, "test">,
    transactionId: string,
  ) => Promise<readonly VerifiedSubscriptionStatus[]>;
}>;

type ServerApiFactory = (environment: Exclude<StoreEnvironment, "test">) => ServerApi;

function providerEnvironment(
  environment: Exclude<StoreEnvironment, "test">,
): Environment {
  return environment === "production" ? Environment.PRODUCTION : Environment.SANDBOX;
}

function protocolError(message: string): AppError {
  return new AppError({
    code: "APPLE_SERVER_API_PROTOCOL_ERROR",
    message,
    statusCode: 502,
  });
}

export function createAppleBillingStatusClient(
  config: RuntimeConfig,
  verifier: AppleBillingVerifier,
  clientFactory?: ServerApiFactory,
): AppleBillingStatusClient {
  const issuerId = config.appleBillingIssuerId;
  const keyId = config.appleBillingKeyId;
  const privateKeyBase64 = config.appleBillingPrivateKeyBase64;
  if (
    !config.appleBillingEnabled ||
    issuerId === undefined ||
    keyId === undefined ||
    privateKeyBase64 === undefined
  ) {
    throw new Error(
      "Apple billing status client was created while Server API is disabled",
    );
  }

  const signingKey = Buffer.from(privateKeyBase64, "base64").toString("utf8");
  const clients = new Map<Exclude<StoreEnvironment, "test">, ServerApi>();
  const client = (environment: Exclude<StoreEnvironment, "test">): ServerApi => {
    const existing = clients.get(environment);
    if (existing !== undefined) {
      return existing;
    }
    const created =
      clientFactory?.(environment) ??
      new AppStoreServerAPIClient(
        signingKey,
        keyId,
        issuerId,
        config.appleBillingBundleId,
        providerEnvironment(environment),
      );
    clients.set(environment, created);
    return created;
  };

  return {
    statuses: async (environment, transactionId) => {
      let response: StatusResponse;
      try {
        response = await client(environment).getAllSubscriptionStatuses(transactionId);
      } catch (cause) {
        throw new AppError({
          cause,
          code: "APPLE_SERVER_API_UNAVAILABLE",
          message: "The App Store Server API is temporarily unavailable.",
          statusCode: 503,
        });
      }
      if (response.bundleId !== config.appleBillingBundleId) {
        throw protocolError("The App Store response belongs to another app.");
      }
      const items =
        response.data?.flatMap((group) => group.lastTransactions ?? []) ?? [];
      return Promise.all(
        items.map(async (item): Promise<VerifiedSubscriptionStatus> => {
          if (
            !Number.isInteger(item.status) ||
            item.status === undefined ||
            item.status < 1 ||
            item.status > 5 ||
            item.signedTransactionInfo === undefined
          ) {
            throw protocolError("The App Store subscription response is incomplete.");
          }
          const transaction = await verifier.verifyTransaction(
            item.signedTransactionInfo,
            environment,
          );
          if (transaction.environment !== environment) {
            throw protocolError(
              "The App Store subscription environment does not match the request.",
            );
          }
          const renewal =
            item.signedRenewalInfo === undefined
              ? undefined
              : await verifier.verifyRenewal(item.signedRenewalInfo, environment);
          return {
            providerStatus: item.status,
            ...(renewal === undefined ? {} : { renewal }),
            transaction,
          };
        }),
      );
    },
  };
}
