import "dotenv/config";
import { readFile } from "node:fs/promises";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";
import { importActivityWorld } from "../modules/npc/outing-repository.js";

async function main() {
  const [filename, activation] = process.argv.slice(2);
  if (!filename || (activation !== undefined && activation !== "--activate"))
    throw new Error(
      "Usage: tsx src/cli/publish-activity-world.ts WORLD.json [--activate]",
    );
  const database = createDatabase(loadConfig());
  try {
    await assertMigrationsCurrent(database);
    const result = await importActivityWorld(
      database,
      JSON.parse(await readFile(filename, "utf8")),
      activation === "--activate",
    );
    process.stdout.write(JSON.stringify(result) + "\n");
  } finally {
    await database.close();
  }
}
void main().catch((error: unknown) => {
  process.stderr.write(
    (error instanceof Error ? error.message : "Activity world import failed") + "\n",
  );
  process.exitCode = 1;
});
