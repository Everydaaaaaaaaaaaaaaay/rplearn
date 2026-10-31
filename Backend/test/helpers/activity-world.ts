import { readFileSync } from "node:fs";
import {
  activityWorldSchema,
  type ActivityWorld,
} from "../../src/modules/npc/activity-world-content.js";

/** Isolated fixtures only. Synthetic approval/photos must never be published. */
export function activityWorldFixture(): ActivityWorld {
  const world = activityWorldSchema.parse(
    JSON.parse(
      readFileSync(
        new URL(
          "../../../Content/ActivityWorld/2026-10-31-places-v1/world.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ),
  );
  const legacy = JSON.parse(
    readFileSync(
      new URL("../../../App/Resources/npc-library-v3.json", import.meta.url),
      "utf8",
    ),
  ) as {
    entries: { story: { titleZh: string; nodes: unknown[] }; reunion: unknown }[];
  };
  const previous = legacy.entries[0];
  if (!previous) throw new Error("Missing original story fixture");
  const stories: unknown[] = [];
  let index = 0;
  for (const place of world.places) {
    place.reviewStatus = "approved";
    place.spaceFacts = ["Synthetic test space; no visual approval"];
    place.mediaId = `${place.id}-photo`;
    place.solitude = [0, 1].map((offset) => ({
      id: `${place.id}-quiet-${String(offset)}`,
      titleZh: "隔离测试的独处",
      english: "A synthetic quiet visit.",
      chinese: "仅用于隔离测试。",
    }));
    world.media.push({
      id: place.mediaId,
      cityId: place.cityId,
      placeId: place.id,
      assetName: `${place.id}.jpg`,
      sourceUrl: "https://example.com/test-photo",
      author: "Test fixture",
      license: "Test fixture only",
      licenseUrl: "https://example.com/license",
      cityEvidence: "Synthetic fixture, not geographical evidence",
      sourceSHA256: "a".repeat(64),
      outputSHA256: "b".repeat(64),
      width: 100,
      height: 100,
      processing: "No real photo",
      reviewStatus: "approved",
      reviewEvidence: ["Test fixture only"],
    });
    for (let count = 0; count < place.populationTarget; count += 1) {
      const person = world.characters[index++];
      if (!person) throw new Error("Missing character fixture");
      const storyId = `fixture-${String(index)}`;
      person.reviewStatus = "approved";
      person.reviewNotes = ["Test fixture only"];
      person.assignment = {
        cityId: place.cityId,
        placeId: place.id,
        storyId,
        nationalityCountryCodes: ["GB"],
        nationalityLabel: person.originalCard.nationality,
        hometown: person.originalCard.hometown ?? "Test fixture",
        localConnection: "settled_here",
        presenceReason: "Synthetic fixture",
        placeAttitude: "Synthetic fixture",
        fit: "conditional",
        fitEvidence: "Synthetic fixture",
        migrationExplanationZh: "仅供隔离测试",
        card: { ...person.originalCard, regionId: place.cityId },
      };
      stories.push({
        id: storyId,
        npcId: person.id,
        placeId: place.id,
        titleZh: previous.story.titleZh,
        nodes: previous.story.nodes,
        reunion: previous.reunion,
        causality: Object.fromEntries(
          [
            "presenceReason",
            "placeAttitude",
            "stayingConstraint",
            "currentGoal",
            "currentState",
            "contactTrigger",
            "characterContinuity",
            "reactionAndChange",
            "spatialContinuity",
            "reunionCommonFacts",
          ].map((key) => [key, "Synthetic test fixture; no editorial approval"]),
        ),
        reviewStatus: "approved",
        reviewEvidence: ["Test fixture only"],
      });
    }
  }
  return activityWorldSchema.parse({
    ...world,
    status: "published",
    releaseId: "test-activity-world",
    stories,
  });
}
