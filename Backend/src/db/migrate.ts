import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import type { DatabaseResource } from "./client.js";

const MIGRATIONS_FOLDER = fileURLToPath(new URL("../../migrations", import.meta.url));
const JOURNAL_PATH = fileURLToPath(
  new URL("../../migrations/meta/_journal.json", import.meta.url),
);

type MigrationJournal = Readonly<{
  entries: readonly unknown[];
}>;

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
  const [row] = await resource.sql<{ count: string }[]>`
    select count(*)::text as count
    from drizzle.__drizzle_migrations
  `;
  const applied = Number.parseInt(row?.count ?? "0", 10);
  const expected = await expectedMigrationCount();

  if (applied !== expected) {
    throw new Error("Database migrations are not current");
  }
}
