import { authoredLibrarySchema } from "./authored-content.js";
export {
  authoredLibrarySchema,
  authoredStorySchema,
  authoredActions,
} from "./authored-content.js";
import { createHash } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { deriveDiversityProfile, personaSignature } from "./persona-diversity.js";

/** Offline CLI-only atomic roster replacement; never called from outing routes. */
export async function importAuthoredLibrary(
  database: DatabaseResource,
  input: unknown,
): Promise<number> {
  const library = authoredLibrarySchema.parse(input);
  return database.sql.begin(async (sql) => {
    await sql`select pg_advisory_xact_lock(hashtextextended('npc-avatar-library', 0))`;
    const manifestHash = createHash("sha256")
      .update(JSON.stringify(library))
      .digest("hex");
    const versions =
      await sql`insert into app.npc_library_versions(version,manifest_hash)
      values(${library.libraryVersion},${manifestHash}) on conflict(version) do update set version=excluded.version
      where app.npc_library_versions.manifest_hash=excluded.manifest_hash returning version`;
    if (versions.length !== 1)
      throw Error("Library version is immutable; publish a new version");
    for (const entry of library.entries) {
      const avatars =
        await sql`select id from app.npc_avatars where id=${entry.avatarId} and enabled
        and profile->>'sha256'=${entry.avatarSHA256} and profile->>'gender'=${entry.card.gender}
        and (profile->>'ageMin')::int <= ${entry.card.age} and (profile->>'ageMax')::int >= ${entry.card.age}
        and profile->>'appearance'=${entry.card.appearance}`;
      if (avatars.length !== 1) throw Error(`Avatar compatibility failed: ${entry.id}`);
      const hash = createHash("sha256")
        .update(JSON.stringify(entry.card))
        .digest("hex");
      const inserted =
        await sql`insert into app.public_npcs(id,traveler_id,card,card_hash,persona_profile,persona_signature,avatar_id)
        values(${entry.id},${entry.travelerId},${JSON.stringify(entry.card)}::jsonb,${hash},${JSON.stringify(deriveDiversityProfile(entry.card))}::jsonb,${personaSignature(entry.card)},${entry.avatarId})
        on conflict(id) do update set id=excluded.id
        where app.public_npcs.card=excluded.card and app.public_npcs.avatar_id=excluded.avatar_id and app.public_npcs.traveler_id=excluded.traveler_id
        returning id`;
      if (inserted.length !== 1)
        throw Error(`Existing identity conflicts: ${entry.id}`);
    }
    // Explicit replacement authorization releases old portrait bindings, never deletes people/messages.
    await sql`update app.public_npcs set avatar_id=null,updated_at=now()
      where avatar_id=any(${library.entries.map((e) => e.avatarId)}::uuid[])
      and not(id=any(${library.entries.map((e) => e.id)}::uuid[]))`;
    // Authoritative scene pool only. Friends, messages and identities remain intact.
    await sql`delete from app.npc_scene_affinities`;
    for (const entry of library.entries)
      await sql`insert into app.npc_scene_affinities(npc_id,region_id,activity_id,category,language,library_version)
      values(${entry.id},${entry.card.regionId},${entry.story.actionId},'social','English',${library.libraryVersion})`;
    return library.entries.length;
  });
}
