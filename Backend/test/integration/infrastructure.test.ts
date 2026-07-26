import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createDatabaseMetricsSource } from "../../src/modules/observability/database-metrics.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

describe.runIf(runIntegrationTests)("runtime infrastructure", () => {
  let dependencies: RuntimeDependencies;

  beforeAll(async () => {
    dependencies = createRuntimeDependencies(loadConfig({ NODE_ENV: "test" }));
    await runMigrations(dependencies.database);
    await dependencies.start();
  });

  afterAll(async () => {
    await dependencies.close();
  });

  it("applies migrations and reaches all dependencies", async () => {
    const results = await Promise.all(
      dependencies.readinessChecks.map(async (check) => {
        await check.check();
        return check.name;
      }),
    );

    expect(results).toEqual(["postgresql", "redis"]);
  });

  it("consumes one-time Redis values exactly once", async () => {
    const key = `integration:one-time:${Date.now().toString()}`;
    await dependencies.redis.putOneTime(key, "value", 10);

    await expect(dependencies.redis.takeOneTime(key)).resolves.toBe("value");
    await expect(dependencies.redis.takeOneTime(key)).resolves.toBeNull();
  });

  it("collects bounded operational state from persisted facts", async () => {
    const snapshot = await createDatabaseMetricsSource(dependencies.database)();
    const values = [
      ...snapshot.aiRequests.flatMap((row) => [
        row.count,
        row.inputTokens,
        row.outputTokens,
      ]),
      ...snapshot.billingEventBacklog.flatMap((row) => [
        row.count,
        row.oldestAgeSeconds,
      ]),
      ...snapshot.billingReconciliationOverdue.map((row) => row.count),
      ...snapshot.jobCounts.map((row) => row.count),
      ...snapshot.oldestPendingJobs.map((row) => row.ageSeconds),
      ...snapshot.subscriptionCounts.map((row) => row.count),
    ];

    expect(values.every((value) => Number.isFinite(value) && value >= 0)).toBe(true);
    expect(
      snapshot.jobCounts.every((row) =>
        [
          "account.purge",
          "auth.email_verification",
          "auth.password_reset",
          "media.delete",
          "other",
        ].includes(row.type),
      ),
    ).toBe(true);
  });
});
