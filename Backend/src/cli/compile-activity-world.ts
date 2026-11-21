import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { z } from "zod";
import type { OutingSnapshot } from "../modules/npc/outing-types.js";
import {
  activityWorldSchema,
  contentHash,
  placeEncounterStorySchema,
  requirePublishedWorld,
} from "../modules/npc/activity-world-content.js";

const fingerprint = z.string().regex(/^[a-f0-9]{64}$/);
const approvalSchema = z.object({
  releaseId: z.string(),
  draftManifestHash: fingerprint,
  decision: z.literal("approved"),
  evidence: z.array(z.string().min(1)).min(1),
  stories: z.array(z.object({ id: z.string(), sha256: fingerprint })).length(200),
  media: z.array(z.object({ id: z.string(), sha256: fingerprint })).min(45),
});

const storyRevisionSchema = z
  .object({
    baseReleaseId: z.string(),
    releaseId: z.string(),
    stories: z.array(placeEncounterStorySchema).min(1),
  })
  .strict();

async function main() {
  const [source, reviewFile, assets, output, appOutput, storyRevisionFile] =
    process.argv.slice(2);
  if (!source || !reviewFile || !assets || !output || !appOutput)
    throw new Error(
      "Usage: compile-activity-world WORLD REVIEW ASSET_DIRECTORY RELEASE APP_RELEASE [STORY_REVISION]",
    );
  const base = activityWorldSchema.parse(JSON.parse(await readFile(source, "utf8")));
  let world = base;
  if (storyRevisionFile) {
    const revision = storyRevisionSchema.parse(
      JSON.parse(await readFile(storyRevisionFile, "utf8")),
    );
    if (
      revision.baseReleaseId !== base.releaseId ||
      revision.releaseId === base.releaseId
    )
      throw new Error("Story revision must name the existing base and a new release");
    const originals = new Map(base.stories.map((story) => [story.id, story]));
    const replacements = new Map(revision.stories.map((story) => [story.id, story]));
    if (replacements.size !== revision.stories.length)
      throw new Error("Story revision contains duplicate IDs");
    for (const story of revision.stories) {
      const original = originals.get(story.id);
      if (original?.npcId !== story.npcId || original.placeId !== story.placeId)
        throw new Error(`Story revision changes the binding: ${story.id}`);
    }
    world = activityWorldSchema.parse({
      ...base,
      releaseId: revision.releaseId,
      stories: base.stories.map((story) => replacements.get(story.id) ?? story),
    });
  }
  const review = approvalSchema.parse(JSON.parse(await readFile(reviewFile, "utf8")));
  if (
    world.status !== "draft" ||
    review.releaseId !== world.releaseId ||
    review.draftManifestHash !== contentHash(world)
  )
    throw new Error("Approval does not match the exact source draft");
  for (const story of world.stories) {
    if (
      review.stories.find((item) => item.id === story.id)?.sha256 !== contentHash(story)
    )
      throw new Error(`Story differs from approved content: ${story.id}`);
    story.reviewStatus = "approved";
    story.reviewEvidence.push(...review.evidence);
  }
  for (const image of world.media) {
    const bytes = await readFile(join(assets, image.assetName));
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    if (
      sha256 !== image.outputSHA256 ||
      review.media.find((item) => item.id === image.id)?.sha256 !== sha256
    )
      throw new Error(`Photograph differs from approved asset: ${image.id}`);
    image.reviewStatus = "approved";
    image.reviewEvidence.push(...review.evidence);
  }
  for (const person of world.characters) {
    person.reviewStatus = "approved";
    person.reviewNotes.push(...review.evidence);
  }
  for (const place of world.places) place.reviewStatus = "approved";
  world.status = "published";
  const release = requirePublishedWorld(world);
  const manifestHash = contentHash(release);
  await writeFile(output, JSON.stringify(release, null, 2) + "\n");
  const previewOutings: OutingSnapshot[] = [];
  const catalogs = release.cities.map((city) => ({
    releaseId: release.releaseId,
    cityId: city.id,
    places: release.places
      .filter((place) => place.cityId === city.id)
      .map((place) => ({
        id: place.id,
        titleZh: place.titleZh,
        category: place.category,
        photo: release.media.find((photo) => photo.id === place.mediaId),
      })),
  }));
  for (const place of release.places) {
    const photo = release.media.find((image) => image.id === place.mediaId),
      solitude = place.solitude[0];
    if (!photo || !solitude) throw new Error("Missing preview place content");
    const base: OutingSnapshot = {
      runId: "00000000-0000-4000-8000-000000000000",
      releaseId: release.releaseId,
      cityId: place.cityId,
      placeId: place.id,
      placeTitleZh: place.titleZh,
      createdAt: "2026-11-15T00:00:00.000Z",
      status: "reserved",
      revision: 0,
      mode: "solitude",
      reason: "quiet_visit",
      npc: null,
      story: null,
      photo,
      solitude,
      nodeId: "start",
      beatIndex: -1,
      choices: [],
    };
    previewOutings.push(base);
    for (const person of release.characters.filter(
      (person) => person.assignment?.placeId === place.id,
    )) {
      const binding = person.assignment;
      const story = release.stories.find((story) => story.id === binding?.storyId);
      if (!binding || !story) throw new Error("Missing preview character content");
      previewOutings.push({
        ...base,
        mode: "first_meeting",
        reason: "encounter",
        npc: {
          id: person.id,
          travelerId: person.travelerId,
          avatar: null,
          card: binding.card,
          createdAt: base.createdAt,
        },
        story: {
          id: story.id,
          titleZh: story.titleZh,
          nodes: story.nodes,
          reunion: story.reunion,
        },
      });
    }
  }
  await writeFile(
    appOutput,
    JSON.stringify(
      {
        schemaVersion: 1,
        releaseId: release.releaseId,
        manifestHash,
        settingVersion: 1,
        preview: { catalogs, outings: previewOutings },
        characters: release.characters.map((person) => {
          if (!person.assignment) throw new Error("Unassigned character");
          return {
            npc: {
              id: person.id,
              travelerId: person.travelerId,
              avatar: null,
              card: person.assignment.card,
              createdAt: "2026-11-15T00:00:00.000Z",
            },
            migrationExplanationZh: person.assignment.migrationExplanationZh,
          };
        }),
      },
      null,
      2,
    ) + "\n",
  );
  process.stdout.write(
    JSON.stringify({
      releaseId: release.releaseId,
      manifestHash,
      characters: release.characters.length,
      places: release.places.length,
    }) + "\n",
  );
}
void main().catch((error: unknown) => {
  process.stderr.write(
    (error instanceof Error ? error.message : "World compilation failed") + "\n",
  );
  process.exitCode = 1;
});
