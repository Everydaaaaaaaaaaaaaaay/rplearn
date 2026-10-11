import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import type { DatabaseResource } from "./client.js";
import { assertCompatibleMigrationInventory } from "./migration-compatibility.js";

const MIGRATIONS_FOLDER = fileURLToPath(new URL("../../migrations", import.meta.url));
const JOURNAL_PATH = fileURLToPath(
  new URL("../../migrations/meta/_journal.json", import.meta.url),
);

type MigrationJournal = Readonly<{
  entries: readonly unknown[];
}>;

export function environmentForMigrations(
  environment: NodeJS.ProcessEnv,
): NodeJS.ProcessEnv {
  const migrationDatabaseUrl = environment.MIGRATION_DATABASE_URL?.trim();
  if (migrationDatabaseUrl === undefined || migrationDatabaseUrl.length === 0) {
    if (environment.NODE_ENV === "production") {
      throw new Error("MIGRATION_DATABASE_URL is required in production");
    }
    return environment;
  }
  return {
    ...environment,
    DATABASE_URL: migrationDatabaseUrl,
  };
}

async function expectedMigrationCount(): Promise<number> {
  const journal = JSON.parse(await readFile(JOURNAL_PATH, "utf8")) as MigrationJournal;
  return journal.entries.length;
}

export async function runMigrations(resource: DatabaseResource): Promise<void> {
  await migrate(resource.database, {
    migrationsFolder: MIGRATIONS_FOLDER,
  });
}

export async function assertMigrationsCurrent(
  resource: DatabaseResource,
): Promise<void> {
  const applied = await resource.sql<{ hash: string; created_at: string }[]>`
    select hash,created_at::text
    from drizzle.__drizzle_migrations
    order by created_at
  `;
  const expected = await expectedMigrationCount();
  assertCompatibleMigrationInventory(expected, applied);
}
