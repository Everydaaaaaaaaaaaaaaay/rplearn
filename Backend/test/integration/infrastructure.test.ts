import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";

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
});
