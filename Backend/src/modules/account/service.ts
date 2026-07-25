import { createHmac, randomBytes } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import type { CredentialSealer } from "../auth/apple/credential-crypto.js";
import type { AppleTokenRevoker } from "../auth/apple/token-revoker.js";
import { createJobPayloadCipher } from "../jobs/crypto.js";
import { ACCOUNT_PURGE_JOB } from "../jobs/types.js";
import { AccountRepository } from "./repository.js";
import type {
  AccountDeletionMode,
  AccountDeletionReceipt,
  AccountExport,
} from "./types.js";

export type AccountService = Readonly<{
  cancelDeletion: (token: string) => Promise<void>;
  exportData: (userId: string) => Promise<AccountExport>;
  processDeletion: (
    payload: Readonly<{ requestId: string; userId: string }>,
  ) => Promise<void>;
  scheduleDeletion: (
    userId: string,
    mode: AccountDeletionMode,
  ) => Promise<AccountDeletionReceipt>;
}>;

type AccountServiceDependencies = Readonly<{
  appleTokenRevoker?: AppleTokenRevoker;
  credentialSealer?: CredentialSealer;
  onAppleRevocationUnavailable?: (
    fields: Readonly<{ reason: string; requestId: string }>,
  ) => void;
}>;

function addDays(date: Date, days: number): Date {
  return new Date(date.getTime() + days * 24 * 60 * 60 * 1000);
}

export function createAccountService(
  config: RuntimeConfig,
  database: DatabaseResource,
  dependencies: AccountServiceDependencies = {},
): AccountService {
  const repository = new AccountRepository(database);
  const jobCipher = createJobPayloadCipher(config);
  const hash = (namespace: string, value: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`${namespace}:${value}`)
      .digest("hex");

  return {
    cancelDeletion: async (token) => {
      const cancelled = await repository.cancelDeletion(
        hash("account-cancellation", token),
        new Date(),
      );
      if (!cancelled) {
        throw new AppError({
          code: "ACCOUNT_DELETION_CANCELLATION_INVALID",
          message: "The account deletion cancellation token is invalid or expired.",
          statusCode: 400,
        });
      }
    },

    exportData: (userId) => repository.exportData(userId, new Date()),

    processDeletion: async (payload) => {
      const work = await repository.beginDeletion(
        payload.requestId,
        payload.userId,
        new Date(),
      );
      if (work === undefined) {
        return;
      }
      if (work.appleCredentials.length > 0) {
        if (
          dependencies.appleTokenRevoker === undefined ||
          dependencies.credentialSealer === undefined
        ) {
          dependencies.onAppleRevocationUnavailable?.({
            reason: "revoker_not_configured",
            requestId: work.requestId,
          });
        } else {
          for (const apple of work.appleCredentials) {
            if (apple.clientId === null) {
              dependencies.onAppleRevocationUnavailable?.({
                reason: "client_id_missing",
                requestId: work.requestId,
              });
              continue;
            }
            await dependencies.appleTokenRevoker.revokeRefreshToken(
              apple.clientId,
              dependencies.credentialSealer.open(apple.credential),
            );
          }
        }
      }
      const finalized = await repository.finalizeDeletion(
        work.requestId,
        work.userId,
        new Date(),
      );
      if (!finalized) {
        throw new Error("AccountDeletionFinalizationFailed");
      }
    },

    scheduleDeletion: async (userId, mode) => {
      const now = new Date();
      const purgeAt =
        mode === "immediate" ? now : addDays(now, config.accountDeletionGraceDays);
      const requestId = newEntityId();
      const cancellationToken =
        mode === "grace_period" ? randomBytes(48).toString("base64url") : null;
      const scheduled = await repository.scheduleDeletion({
        cancellationTokenHash:
          cancellationToken === null
            ? null
            : hash("account-cancellation", cancellationToken),
        job: jobCipher.prepare(
          ACCOUNT_PURGE_JOB,
          {
            requestId,
            userId,
          },
          {
            availableAt: purgeAt,
            maxAttempts: 12,
            uniqueKey: `account-deletion:${requestId}`,
            userId,
          },
        ),
        purgeAt,
        requestId,
        userId,
        userReferenceHash: hash("deleted-account", userId),
      });
      if (!scheduled) {
        throw new AppError({
          code: "ACCOUNT_UNAVAILABLE",
          message: "This account is not available.",
          statusCode: 409,
        });
      }
      return {
        cancellationToken,
        purgeAt,
        requestId,
      };
    },
  };
}
