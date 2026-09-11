import { createHash } from "node:crypto";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { publicCard } from "./card-schema.js";
import { deriveDiversityProfile, personaSignature } from "./persona-diversity.js";
import { isValidTravelerId } from "./traveler-id.js";

export const authoredActions = [
  "park-route",
  "park-seat",
  "park-notes",
  "pond-reflection",
  "pond-sketch",
  "pond-postcard",
  "rain-weather",
  "rain-pastry",
  "rain-napkin",
] as const;
const cities = [
  "london",
  "melbourne",
  "newyork",
  "capetown",
  "singapore",
  "dublin",
  "edinburgh",
  "vancouver",
  "auckland",
  "nairobi",
  "toronto",
  "sydney",
  "neworleans",
  "manchester",
  "kingston",
];
const beat = z
  .object({
    speaker: z.enum(["narrator", "npc"]),
    english: z.string().trim().min(1).max(420),
    chinese: z.string().trim().min(1).max(260),
  })
  .strict();
const choice = z
  .object({
    english: z.string().trim().min(1).max(180),
    chinese: z.string().trim().min(1).max(100),
    next: z.string(),
  })
  .strict();
const node = z
  .object({
    id: z.string(),
    beats: z.array(beat).min(4).max(6),
    choices: z.array(choice).max(2),
  })
  .strict();
export const authoredStorySchema = z
  .object({
    titleZh: z.string().trim().min(1).max(80),
    actionId: z.enum(authoredActions),
    nodes: z.array(node).length(7),
  })
  .strict()
  .superRefine((story, ctx) => {
    const edges: Record<string, string[]> = {
      start: ["a", "b"],
      a: ["aa", "ab"],
      b: ["ba", "bb"],
      aa: [],
      ab: [],
      ba: [],
      bb: [],
    };
    if (new Set(story.nodes.map((n) => n.id)).size !== 7)
      ctx.addIssue({ code: "custom", message: "Duplicate story nodes" });
    for (const n of story.nodes) {
      if (
        !edges[n.id] ||
        JSON.stringify(n.choices.map((c) => c.next)) !== JSON.stringify(edges[n.id])
      )
        ctx.addIssue({ code: "custom", message: "Invalid story edges" });
      if (
        n.beats.filter((b) => b.speaker === "npc").length < 2 ||
        !n.beats.some((b) => b.speaker === "narrator")
      )
        ctx.addIssue({ code: "custom", message: "Missing dialogue or narration" });
    }
  });
export const authoredLibrarySchema = z
  .object({
    version: z.literal(1),
    libraryVersion: z.string().regex(/^[a-z0-9-]{1,80}$/),
    entries: z
      .array(
        z
          .object({
            id: z.uuid(),
            travelerId: z.string().refine(isValidTravelerId),
            avatarId: z.uuid(),
            avatarSHA256: z.string().regex(/^[a-f0-9]{64}$/),
            card: publicCard,
            summaryZh: z.string().min(1).max(600),
            story: authoredStorySchema,
          })
          .strict(),
      )
      .length(200),
  })
  .strict()
  .superRefine((library, ctx) => {
    for (const key of ["id", "travelerId", "avatarId"] as const)
      if (new Set(library.entries.map((e) => e[key])).size !== 200)
        ctx.addIssue({ code: "custom", message: "Duplicate " + key });
    for (const entry of library.entries)
      if (
        !cities.includes(entry.card.regionId) ||
        !entry.card.languages.includes("English")
      )
        ctx.addIssue({ code: "custom", message: "Unsupported city/language" });
    for (const city of cities)
      for (const action of authoredActions)
        if (
          !library.entries.some(
            (e) => e.card.regionId === city && e.story.actionId === action,
          )
        )
          ctx.addIssue({
            code: "custom",
            message: `Unreachable city/action ${city}/${action}`,
          });
  });

/** Offline CLI-only atomic roster replacement; never called from outing routes. */
export async function importAuthoredLibrary(
  database: DatabaseResource,
  input: unknown,
): Promise<number> {
  const library = authoredLibrarySchema.parse(input);
  return database.sql.begin(async (sql) => {
    await sql`select pg_advisory_xact_lock(hashtextextended('npc-avatar-library', 0))`;
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
    // Authoritative scene pool only. Friends, messages and identities remain intact.
    await sql`delete from app.npc_scene_affinities`;
    for (const entry of library.entries)
      await sql`insert into app.npc_scene_affinities(npc_id,region_id,activity_id,category,language)
      values(${entry.id},${entry.card.regionId},${entry.story.actionId},'social','English')`;
    return library.entries.length;
  });
}
