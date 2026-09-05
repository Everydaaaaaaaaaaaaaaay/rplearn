import "dotenv/config";
import { readFile } from "node:fs/promises";
import {
  avatarManifestSchema,
  importAvatarManifest,
} from "../modules/npc/avatar-import.js";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";

async function main(): Promise<void> {
  const manifestPath = process.argv[2];
  if (manifestPath === undefined) {
    throw new Error("Usage: pnpm npc-avatars:import -- /absolute/path/avatars.json");
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

  const manifest = avatarManifestSchema.parse(
    JSON.parse(await readFile(manifestPath, "utf8")) as unknown,
  );
  const database = createDatabase(config);
  try {
    await assertMigrationsCurrent(database);
    const imported = await importAvatarManifest(database, manifest);
    process.stdout.write(
      `${JSON.stringify({ imported, supplied: manifest.avatars.length })}\n`,
    );
  } finally {
    await database.close();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "AvatarImportFailed"}\n`,
  );
  process.exitCode = 1;
});
