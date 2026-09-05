import "dotenv/config";
import { readFile } from "node:fs/promises";
import { z } from "zod";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";

const manifestSchema = z
  .object({
    avatars: z
      .array(
        z
          .object({
            enabled: z.boolean().default(true),
            id: z.uuid(),
            tags: z
              .array(z.string().trim().min(1).max(80))
              .max(32)
              .refine(
                (tags) => new Set(tags).size === tags.length,
                "Tags must be unique",
              ),
            url: z
              .url()
              .refine((url) => url.startsWith("https://"), "HTTPS is required"),
          })
          .strict(),
      )
      .min(1)
      .max(10_000),
    version: z.literal(1),
  })
  .strict();

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

  const manifest = manifestSchema.parse(
    JSON.parse(await readFile(manifestPath, "utf8")) as unknown,
  );
  const database = createDatabase(config);
  try {
    await assertMigrationsCurrent(database);
    let imported = 0;
    for (const avatar of manifest.avatars) {
      const rows = await database.sql<{ id: string }[]>`
        insert into app.npc_avatars (id, image_url, tags, enabled)
        values (
          ${avatar.id},
          ${avatar.url},
          ${JSON.stringify(avatar.tags)}::jsonb,
          ${avatar.enabled}
        )
        on conflict (id) do update
        set image_url = excluded.image_url,
            tags = excluded.tags,
            enabled = excluded.enabled,
            updated_at = now()
        where not exists (
          select 1 from app.public_npcs where avatar_id = excluded.id
        )
        returning id::text
      `;
      imported += rows.length;
    }
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
