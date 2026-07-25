import "dotenv/config";
import { setTimeout as delay } from "node:timers/promises";
import pino from "pino";
import { createLoggerOptions } from "./app/logger.js";
import { ConfigurationError, loadConfig } from "./config/env.js";
import { createDatabase } from "./db/client.js";
import { assertMigrationsCurrent } from "./db/migrate.js";
import { createSmtpAuthNotifier } from "./modules/auth/notifier.js";
import { createJobPayloadCipher } from "./modules/jobs/crypto.js";
import { JobRepository } from "./modules/jobs/repository.js";
import { JobWorker } from "./modules/jobs/worker.js";
import { newEntityId } from "./shared/id.js";
import { createAccountService } from "./modules/account/service.js";
import { createCredentialSealer } from "./modules/auth/apple/credential-crypto.js";
import { createAppleTokenRevoker } from "./modules/auth/apple/token-revoker.js";

async function main(): Promise<void> {
  let config: ReturnType<typeof loadConfig>;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigurationError) {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
      return;
    }
    throw error;
  }

  const logger = pino(createLoggerOptions(config.logLevel));
  const database = createDatabase(config);
  const controller = new AbortController();
  const workerId = `worker-${newEntityId()}`;
  const accountService = createAccountService(config, database, {
    onAppleRevocationUnavailable: (fields) => {
      logger.warn(fields, "Apple token revocation was unavailable during deletion");
    },
    ...(config.appleAuthEnabled
      ? {
          appleTokenRevoker: await createAppleTokenRevoker(config),
          credentialSealer: createCredentialSealer(config),
        }
      : {}),
  });
  const worker = new JobWorker({
    cipher: createJobPayloadCipher(config),
    config,
    logger,
    notifier: createSmtpAuthNotifier(config),
    processAccountPurge: accountService.processDeletion,
    repository: new JobRepository(database),
    workerId,
  });
  let closing = false;

  const shutdown = (signal: NodeJS.Signals): void => {
    if (closing) {
      return;
    }
    closing = true;
    logger.info({ signal, workerId }, "Worker shutdown started");
    controller.abort();
  };
  process.once("SIGINT", () => shutdown("SIGINT"));
  process.once("SIGTERM", () => shutdown("SIGTERM"));

  try {
    await assertMigrationsCurrent(database);
    logger.info({ workerId }, "Worker started");
    while (!controller.signal.aborted) {
      try {
        const result = await worker.runOnce();
        if (result !== "idle") {
          continue;
        }
      } catch (error) {
        logger.error(
          {
            errorName: error instanceof Error ? error.name : "UnknownError",
            workerId,
          },
          "Worker polling failed",
        );
      }

      try {
        await delay(config.jobPollIntervalMs, undefined, {
          signal: controller.signal,
        });
      } catch (error) {
        if (!(error instanceof Error) || error.name !== "AbortError") {
          throw error;
        }
      }
    }
  } finally {
    await database.close();
    logger.info({ workerId }, "Worker stopped");
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.name : "UnknownWorkerError"}\n`,
  );
  process.exitCode = 1;
});
