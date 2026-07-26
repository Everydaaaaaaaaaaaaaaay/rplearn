import "dotenv/config";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createRuntimeDependencies } from "../infrastructure/runtime-dependencies.js";
import { createDeepSeekClient } from "../modules/ai/deepseek/client.js";
import { createSmtpAuthNotifier } from "../modules/auth/notifier.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import {
  createProductionReadinessChecks,
  productionReadinessFailureReport,
  runProductionReadinessChecks,
  type ProductionReadinessReport,
} from "../modules/operations/production-readiness.js";

function writeReport(report: ProductionReadinessReport): void {
  process.stdout.write(`${JSON.stringify(report)}\n`);
}

async function main(): Promise<void> {
  let config: ReturnType<typeof loadConfig>;
  try {
    config = loadConfig();
  } catch (error) {
    writeReport(
      productionReadinessFailureReport(
        error instanceof ConfigurationError
          ? "CONFIGURATION_INVALID"
          : "CONFIGURATION_LOAD_FAILED",
      ),
    );
    process.exitCode = 1;
    return;
  }

  if (config.nodeEnv !== "production") {
    writeReport(productionReadinessFailureReport("PRODUCTION_MODE_REQUIRED"));
    process.exitCode = 1;
    return;
  }

  const dependencies = createRuntimeDependencies(config);
  try {
    const report = await runProductionReadinessChecks(
      createProductionReadinessChecks(config, {
        ai: createDeepSeekClient(config),
        database: dependencies.database,
        media: createMediaObjectStore(config),
        redis: dependencies.redis,
        smtp: createSmtpAuthNotifier(config),
      }),
      config.readinessTimeoutMs,
    );
    writeReport(report);
    if (!report.passed) {
      process.exitCode = 1;
    }
  } finally {
    await dependencies.close();
  }
}

void main().catch(() => {
  writeReport(productionReadinessFailureReport("READINESS_RUNNER_FAILED"));
  process.exitCode = 1;
});
