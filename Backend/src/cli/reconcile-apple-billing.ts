import "dotenv/config";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";
import { createAppleBillingStatusClient } from "../modules/billing/apple/server-api-client.js";
import { createAppleBillingVerifier } from "../modules/billing/apple/verifier.js";
import { createBillingService } from "../modules/billing/service.js";

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
  if (!config.appleBillingEnabled) {
    throw new Error("AppleBillingDisabled");
  }

  const database = createDatabase(config);
  try {
    await assertMigrationsCurrent(database);
    const verifier = createAppleBillingVerifier(config);
    const service = createBillingService(
      database,
      verifier,
      createAppleBillingStatusClient(config, verifier),
      {
        activeHours: config.appleBillingReconcileActiveHours,
        batchSize: config.appleBillingReconcileBatchSize,
        inactiveHours: config.appleBillingReconcileInactiveHours,
        retryMinutes: config.appleBillingReconcileRetryMinutes,
      },
    );
    const result = await service.reconcileAppleSubscriptions();
    process.stdout.write(`${JSON.stringify(result)}\n`);
    if (result.failed > 0) {
      process.exitCode = 1;
    }
  } finally {
    await database.close();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.name : "UnknownBillingReconciliationError"}\n`,
  );
  process.exitCode = 1;
});
