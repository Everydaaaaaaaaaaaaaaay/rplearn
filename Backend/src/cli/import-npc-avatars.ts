import "dotenv/config";
import { readFile } from "node:fs/promises";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";
import { verifyAvatarFile } from "../modules/npc/avatar-file.js";
import { avatarManifestSchema } from "../modules/npc/avatar-catalog.js";

async function main(): Promise<void> {
  const args = process.argv.slice(2).filter((arg) => arg !== "--");
  const manifestPath = args.find((arg) => arg !== "--dry-run");
  if (!manifestPath)
    throw new Error("Usage: pnpm npc-avatars:import -- manifest.json [--dry-run]");
  const manifest = avatarManifestSchema.parse(
    JSON.parse(await readFile(manifestPath, "utf8")) as unknown,
  );
  if (args.includes("--dry-run")) {
    process.stdout.write(
      `${JSON.stringify({ validated: manifest.avatars.length, families: new Set(manifest.avatars.map((asset) => asset.familyId)).size })}\n`,
    );
    return;
  }
  for (const avatar of manifest.avatars) {
    await verifyAvatarFile(avatar.url, avatar.sha256);
  }
  const database = createDatabase(loadConfig());
  try {
    await assertMigrationsCurrent(database);
    // Atomic import: validation/conflicts cannot leave a partially published catalog.
    await database.sql.begin(async (sql) => {
      for (const avatar of [...manifest.avatars].sort((a, b) =>
        a.id.localeCompare(b.id),
      )) {
        const rows = await sql`
          insert into app.npc_avatars (id, family_id, sha256, image_url, metadata, enabled, reserved)
          values (${avatar.id}, ${avatar.familyId}, ${avatar.sha256}, ${avatar.url},
            ${JSON.stringify(avatar.metadata)}::jsonb, ${avatar.enabled}, ${avatar.reserved})
          on conflict (id) do update
          set metadata = excluded.metadata, enabled = excluded.enabled, reserved = excluded.reserved, updated_at = now()
          where app.npc_avatars.family_id = excluded.family_id
            and app.npc_avatars.image_url = excluded.image_url
            and app.npc_avatars.sha256 = excluded.sha256
          returning id
        `;
        if (!rows.length)
          throw new Error(
            `Immutable avatar content conflict: ${avatar.id}. Create a new asset; do not overwrite a bound image.`,
          );
      }
    });
    process.stdout.write(`${JSON.stringify({ imported: manifest.avatars.length })}\n`);
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
