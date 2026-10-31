import { createHash } from "node:crypto";
import { z } from "zod";
import { publicCard } from "./card-schema.js";
import { authoredStorySchema, authoredReunionSchema } from "./authored-content.js";
import { isValidTravelerId } from "./traveler-id.js";

const id = z.string().regex(/^[a-z0-9][a-z0-9-]{1,100}$/);
const hash = z.string().regex(/^[a-f0-9]{64}$/);
const text = z.string().trim().min(1).max(4_000);
const reviewStatus = z.enum(["draft", "approved", "rejected"]);
const solitude = z.object({ id, titleZh: text, english: text, chinese: text }).strict();

export const activityPlaceSchema = z
  .object({
    id,
    cityId: id,
    titleZh: text,
    category: z.enum([
      "cafe",
      "market",
      "bookshop",
      "park",
      "street",
      "community",
      "transport",
    ]),
    populationTarget: z.number().int().min(3).max(30),
    reviewStatus,
    spaceFacts: z.array(text).max(30),
    solitude: z.array(solitude).max(20),
    mediaId: id.optional(),
  })
  .strict();

const causality = z
  .object({
    presenceReason: text,
    placeAttitude: text,
    stayingConstraint: text,
    currentGoal: text,
    currentState: text,
    contactTrigger: text,
    characterContinuity: text,
    reactionAndChange: text,
    spatialContinuity: text,
    reunionCommonFacts: text,
  })
  .strict();

export const placeEncounterStorySchema = z
  .object({
    id,
    npcId: z.uuid(),
    placeId: id,
    titleZh: text,
    nodes: authoredStorySchema.shape.nodes,
    reunion: authoredReunionSchema,
    causality,
    reviewStatus,
    reviewEvidence: z.array(text),
  })
  .strict()
  .superRefine((story, context) => {
    // Share the existing graph/beat rules without inheriting v1's action taxonomy.
    const graph = authoredStorySchema.safeParse({
      titleZh: story.titleZh,
      actionId: "park-route",
      nodes: story.nodes,
    });
    if (!graph.success)
      for (const issue of graph.error.issues)
        context.addIssue({ code: "custom", message: issue.message, path: issue.path });
  });

const assignment = z
  .object({
    cityId: id,
    placeId: id,
    storyId: id,
    nationalityCountryCodes: z
      .array(z.string().regex(/^[A-Z]{2}$/))
      .min(1)
      .max(3),
    nationalityLabel: text,
    hometown: text,
    localConnection: z.enum(["grew_up_here", "settled_here", "temporary_stay"]),
    presenceReason: text,
    placeAttitude: text,
    fit: z.enum(["natural", "conditional"]),
    fitEvidence: text,
    migrationExplanationZh: text,
    card: publicCard,
  })
  .strict();

const character = z
  .object({
    id: z.uuid(),
    travelerId: z.string().refine(isValidTravelerId),
    avatarId: z.uuid(),
    avatarSHA256: hash,
    sourceCardHash: hash,
    originalCard: publicCard,
    legacyActionId: id,
    legacyStoryTitleZh: text,
    reviewStatus: z.enum(["pending", "approved", "revise"]),
    reviewNotes: z.array(text),
    assignment: assignment.optional(),
  })
  .strict();

const photo = z
  .object({
    id,
    cityId: id,
    placeId: id,
    assetName: z.string().regex(/^[a-z0-9-]+\.(jpg|jpeg|png|webp)$/),
    sourceUrl: z.url().startsWith("https://"),
    author: text,
    license: text,
    licenseUrl: z.url().startsWith("https://"),
    cityEvidence: text,
    sourceSHA256: hash,
    outputSHA256: hash,
    width: z.number().int().positive(),
    height: z.number().int().positive(),
    processing: text,
    reviewStatus,
    reviewEvidence: z.array(text),
  })
  .strict();

export const activityWorldSchema = z
  .object({
    schemaVersion: z.literal(1),
    releaseId: id,
    status: z.enum(["draft", "published"]),
    sourceLibraryVersion: id,
    sourceSHA256: hash,
    cities: z
      .array(
        z
          .object({
            id,
            nameZh: text,
            populationTarget: z.number().int().min(9).max(30),
          })
          .strict(),
      )
      .length(15),
    places: z.array(activityPlaceSchema).min(45).max(75),
    characters: z.array(character).length(200),
    stories: z.array(placeEncounterStorySchema).max(200),
    media: z.array(photo).max(75),
  })
  .strict()
  .superRefine((world, context) => {
    const fail = (message: string) => context.addIssue({ code: "custom", message });
    for (const [label, values] of [
      ["city", world.cities.map((item) => item.id)],
      ["place", world.places.map((item) => item.id)],
      ["character", world.characters.map((item) => item.id)],
      ["traveler", world.characters.map((item) => item.travelerId)],
      ["avatar", world.characters.map((item) => item.avatarId)],
      ["story", world.stories.map((item) => item.id)],
      ["media", world.media.map((item) => item.id)],
      ["media asset", world.media.map((item) => item.assetName)],
    ] as const)
      if (new Set(values).size !== values.length) fail(`Duplicate ${label}`);
    const cities = new Set(world.cities.map((city) => city.id));
    const places = new Map(world.places.map((place) => [place.id, place]));
    const people = new Map(world.characters.map((person) => [person.id, person]));
    const stories = new Map(world.stories.map((story) => [story.id, story]));
    const media = new Map(world.media.map((image) => [image.id, image]));
    if (world.cities.reduce((total, city) => total + city.populationTarget, 0) !== 200)
      fail("City population targets must sum to 200");
    for (const city of world.cities) {
      const local = world.places.filter((place) => place.cityId === city.id);
      if (local.length < 3 || local.length > 5)
        fail(`Expected 3–5 places in ${city.id}`);
      if (
        local.reduce((total, place) => total + place.populationTarget, 0) !==
        city.populationTarget
      )
        fail(`Place targets do not match city target: ${city.id}`);
    }
    for (const place of world.places) {
      if (!cities.has(place.cityId)) fail(`Unknown city: ${place.id}`);
      const image = place.mediaId ? media.get(place.mediaId) : undefined;
      if (
        place.mediaId &&
        (!image || image.placeId !== place.id || image.cityId !== place.cityId)
      )
        fail(`Photo must belong to the exact place and city: ${place.id}`);
      if (new Set(place.solitude.map((item) => item.id)).size !== place.solitude.length)
        fail(`Duplicate solitude story: ${place.id}`);
      if (
        world.status === "published" &&
        (place.reviewStatus !== "approved" ||
          !place.spaceFacts.length ||
          place.solitude.length < 2 ||
          image?.reviewStatus !== "approved" ||
          !image.reviewEvidence.length)
      )
        fail(`Place is not release-ready: ${place.id}`);
    }
    for (const person of world.characters) {
      if (contentHash(person.originalCard) !== person.sourceCardHash)
        fail(`Original character baseline changed: ${person.id}`);
      const binding = person.assignment;
      if (!binding) {
        if (world.status === "published") fail(`Unassigned character: ${person.id}`);
        continue;
      }
      const place = places.get(binding.placeId);
      const story = stories.get(binding.storyId);
      if (
        !place ||
        place.cityId !== binding.cityId ||
        binding.card.regionId !== binding.cityId
      )
        fail(`Character/place city mismatch: ${person.id}`);
      if (!story || story.npcId !== person.id || story.placeId !== binding.placeId)
        fail(`Character/story binding mismatch: ${person.id}`);
      for (const key of [
        "name",
        "age",
        "gender",
        "appearance",
        "occupation",
        "personality",
        "hobbies",
        "personaVoice",
      ] as const)
        if (
          canonicalJSON(binding.card[key]) !== canonicalJSON(person.originalCard[key])
        )
          fail(
            `Core character trait cannot change to fit a place: ${person.id}/${key}`,
          );
      if (
        world.status === "published" &&
        (person.reviewStatus !== "approved" ||
          !person.reviewNotes.length ||
          story?.reviewStatus !== "approved" ||
          !story.reviewEvidence.length)
      )
        fail(`Character or story is not release-ready: ${person.id}`);
    }
    for (const story of world.stories)
      if (!people.has(story.npcId) || !places.has(story.placeId))
        fail(`Orphan story: ${story.id}`);
    for (const image of world.media)
      if (places.get(image.placeId)?.cityId !== image.cityId)
        fail(`Orphan or cross-city photo: ${image.id}`);
    if (world.status === "published") {
      for (const place of world.places)
        if (
          world.characters.filter((person) => person.assignment?.placeId === place.id)
            .length < 3
        )
          fail(`Fewer than three characters at ${place.id}`);
      for (const city of world.cities)
        if (
          world.characters.filter((person) => person.assignment?.cityId === city.id)
            .length !== city.populationTarget
        )
          fail(`Character count differs from city target: ${city.id}`);
      if (world.stories.length !== 200)
        fail("Published world needs one first-meeting story per character");
    }
  });

export type ActivityWorld = z.infer<typeof activityWorldSchema>;
export type ActivityPlace = ActivityWorld["places"][number];
export type PlaceEncounterStory = ActivityWorld["stories"][number];

export function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object")
    return `{${Object.entries(value)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([key, item]) => `${JSON.stringify(key)}:${canonicalJSON(item)}`)
      .join(",")}}`;
  return JSON.stringify(value) ?? "null";
}

export function contentHash(value: unknown): string {
  return createHash("sha256").update(canonicalJSON(value)).digest("hex");
}

/** A draft is inspectable, but cannot accidentally become a discoverable world. */
export function requirePublishedWorld(input: unknown): ActivityWorld {
  const world = activityWorldSchema.parse(input);
  if (world.status !== "published") throw new Error("Activity world is still a draft");
  return world;
}
