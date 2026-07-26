import { describe, expect, it } from "vitest";
import { loadDatabaseConnectionConfig } from "../../src/config/env.js";
import { environmentForMigrations } from "../../src/db/migrate.js";

describe("migration database authority", () => {
  it("uses a separate migration credential when one is provided", () => {
    const runtimeUrl = "postgres://runtime:runtime@database/lingotrip";
    const migrationUrl = "postgres://migrator:migrator@database/lingotrip";
    const environment = {
      DATABASE_URL: runtimeUrl,
      MIGRATION_DATABASE_URL: migrationUrl,
    };

    expect(environmentForMigrations(environment)).toEqual({
      DATABASE_URL: migrationUrl,
      MIGRATION_DATABASE_URL: migrationUrl,
    });
    expect(environment.DATABASE_URL).toBe(runtimeUrl);
  });

  it("keeps the development credential when the migration override is empty", () => {
    const environment = {
      DATABASE_URL: "postgres://local:local@database/lingotrip",
      MIGRATION_DATABASE_URL: " ",
    };

    expect(environmentForMigrations(environment)).toBe(environment);
  });

  it("loads a production migration config without unrelated application secrets", () => {
    const migrationUrl = "postgres://migrator:migrator@database/lingotrip";

    expect(
      loadDatabaseConnectionConfig(
        environmentForMigrations({
          MIGRATION_DATABASE_URL: migrationUrl,
          NODE_ENV: "production",
        }),
      ),
    ).toMatchObject({
      databaseMaxConnections: 10,
      databaseUrl: migrationUrl,
    });
  });

  it("does not let production migrations fall back to the runtime credential", () => {
    expect(() =>
      environmentForMigrations({
        DATABASE_URL: "postgres://runtime:runtime@database/lingotrip",
        NODE_ENV: "production",
      }),
    ).toThrow("MIGRATION_DATABASE_URL is required in production");
  });
});
