import "dotenv/config";
import { readFile } from "node:fs/promises";
import {
  authoredLibrarySchema,
  importAuthoredLibrary,
} from "../modules/npc/authored-library-repository.js";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";

async function main(): Promise<void> {
  const manifestPath = process.argv[2];
  if (manifestPath === undefined) {
    throw new Error(
      "Usage: tsx src/cli/import-npc-library.ts /absolute/path/library.json",
    );
  }
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

  const manifest = authoredLibrarySchema.parse(
    JSON.parse(await readFile(manifestPath, "utf8")) as unknown,
  );
  const database = createDatabase(config);
  try {
    await assertMigrationsCurrent(database);
    const imported = await importAuthoredLibrary(database, manifest);
    process.stdout.write(
      `${JSON.stringify({ imported, supplied: manifest.entries.length })}\n`,
    );
  } finally {
    await database.close();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "LibraryImportFailed"}\n`,
  );
  process.exitCode = 1;
});
