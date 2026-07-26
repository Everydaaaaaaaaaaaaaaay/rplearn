import { describe, expect, it } from "vitest";
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
});
