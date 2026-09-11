import { z } from "zod";
import { publicCard } from "./card-schema.js";
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
    if (story.nodes.find((n) => n.id === "start")?.beats[0]?.speaker !== "narrator")
      ctx.addIssue({ code: "custom", message: "Opening must start with narration" });
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
export const authoredReunionSchema = z
  .object({
    titleZh: z.string().trim().min(1).max(80),
    beats: z.array(beat).min(4).max(6),
  })
  .strict()
  .superRefine((value, ctx) => {
    if (
      value.beats[0]?.speaker !== "narrator" ||
      value.beats.filter((b) => b.speaker === "npc").length < 2
    )
      ctx.addIssue({
        code: "custom",
        message: "Reunion needs opening narration and dialogue",
      });
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
            reunion: authoredReunionSchema,
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
