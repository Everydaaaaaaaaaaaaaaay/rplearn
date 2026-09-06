import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";

const profileSchema = z
  .object({
    ageMin: z.number().int().min(14).max(85),
    ageMax: z.number().int().min(14).max(85),
    gender: z.enum(["female", "male", "other"]),
    appearance: z.string().trim().min(1).max(2000),
    styleVersion: z.string().trim().min(1).max(100),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
  })
  .strict()
  .refine((value) => value.ageMin <= value.ageMax, "Invalid age interval");
const avatarSchema = z
  .object({
    id: z.uuid(),
    url: z.url().refine((url) => url.startsWith("https://"), "HTTPS is required"),
    tags: z
      .array(z.string().trim().min(1).max(80))
      .max(32)
      .refine((tags) => new Set(tags).size === tags.length, "Tags must be unique"),
    enabled: z.boolean().default(true),
  })
  .strict();
export const avatarManifestSchema = z
  .discriminatedUnion("version", [
    z
      .object({
        version: z.literal(1),
        avatars: z.array(avatarSchema).min(1).max(10000),
      })
      .strict(),
    z
      .object({
        version: z.literal(2),
        avatars: z
          .array(avatarSchema.extend({ profile: profileSchema }))
          .min(1)
          .max(10000),
      })
      .strict(),
  ])
  .refine(
    (manifest) =>
      new Set(manifest.avatars.map((avatar) => avatar.id)).size ===
      manifest.avatars.length,
    "Duplicate avatar IDs",
  );

// One transaction: never silently import only part of a release. Bound visual identities are immutable.
export async function importAvatarManifest(
  database: DatabaseResource,
  input: unknown,
): Promise<number> {
  const manifest = avatarManifestSchema.parse(input);
  return database.sql.begin(async (sql) => {
    // Separate statement ensures bound-identity checks use a snapshot after ongoing registrations finish.
    await sql`select pg_advisory_xact_lock(hashtextextended('npc-avatar-library', 0))`;
    for (const avatar of manifest.avatars) {
      const profile = "profile" in avatar ? avatar.profile : null;
      const rows = await sql<{ id: string }[]>`
        insert into app.npc_avatars (id, image_url, tags, enabled, profile)
        values (${avatar.id}, ${avatar.url}, ${JSON.stringify(avatar.tags)}::jsonb, ${avatar.enabled}, ${JSON.stringify(profile)}::jsonb)
        on conflict (id) do update set image_url = excluded.image_url, tags = excluded.tags,
          enabled = excluded.enabled, profile = excluded.profile, updated_at = now()
        where not exists (select 1 from app.public_npcs where avatar_id = excluded.id)
          or (app.npc_avatars.image_url = excluded.image_url and app.npc_avatars.tags = excluded.tags
            and app.npc_avatars.profile is not distinct from excluded.profile and app.npc_avatars.enabled = excluded.enabled)
        returning id::text
      `;
      if (rows.length !== 1)
        throw new Error(`Bound avatar is immutable: ${avatar.id}; use a new asset ID`);
    }
    // Registration takes the library lock before writing queue rows; worker claims commit before matching.
    // Publish pixels/metadata and wake durable requests atomically in the same lock order.
    await sql`update app.npc_pending_avatars set next_attempt_at = now()`;
    return manifest.avatars.length;
  });
}
