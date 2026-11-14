import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  activityWorldSchema,
  canonicalJSON,
  contentHash,
  requirePublishedWorld,
} from "../../src/modules/npc/activity-world-content.js";
import { nationalityCountryCodes } from "../../src/modules/npc/country-codes.js";
import { activityWorldFixture } from "../helpers/activity-world.js";

const source = JSON.parse(
  readFileSync(
    new URL(
      "../../../Content/ActivityWorld/2026-10-31-places-v1/world.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as unknown;
const legacy = JSON.parse(
  readFileSync(
    new URL("../../../App/Resources/npc-library-v3.json", import.meta.url),
    "utf8",
  ),
) as { entries: { story: { titleZh: string; nodes: unknown[] }; reunion: unknown }[] };

function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error("Missing test fixture");
  return value;
}

function assignedDraft() {
  const world = activityWorldSchema.parse(structuredClone(source));
  for (const character of world.characters) delete character.assignment;
  const person = required(world.characters[0]),
    place = required(world.places[0]),
    previous = required(legacy.entries[0]);
  const story = {
    id: "test-first-meeting",
    npcId: person.id,
    placeId: place.id,
    titleZh: previous.story.titleZh,
    nodes: previous.story.nodes,
    reunion: previous.reunion,
    reviewStatus: "draft",
    reviewEvidence: [],
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
      ].map((key) => [key, "Test fixture, not editorial approval"]),
    ),
  };
  const assignment = {
    cityId: place.cityId,
    placeId: place.id,
    storyId: story.id,
    nationalityCountryCodes: ["GB"],
    nationalityLabel: "British",
    hometown: "London",
    localConnection: "grew_up_here",
    presenceReason: "Test fixture",
    placeAttitude: "Test fixture",
    fit: "conditional",
    fitEvidence: "Test fixture",
    migrationExplanationZh: "测试夹具",
    card: {
      ...person.originalCard,
      regionId: place.cityId,
      nationality: "British",
      hometown: "London",
    },
  };
  return {
    ...world,
    stories: [story],
    characters: [{ ...person, assignment }, ...world.characters.slice(1)],
  };
}

describe("place-bound activity content admission", () => {
  it("captures all 200 existing identities without making unfinished content discoverable", () => {
    const world = activityWorldSchema.parse(source);
    expect(world.characters).toHaveLength(200);
    expect(world.places).toHaveLength(54);
    expect(world.characters.every((person) => person.reviewStatus !== "approved")).toBe(
      true,
    );
    expect(() => requirePublishedWorld(source)).toThrow("still a draft");
    expect(
      activityWorldSchema.safeParse({ ...world, status: "published" }).success,
    ).toBe(false);
  });

  it("detects changes to the captured baseline and duplicate identity/portrait allocations", () => {
    const changed = activityWorldSchema.parse(structuredClone(source));
    required(changed.characters[0]).originalCard.personality =
      "Everyone loves chatting in cafes";
    expect(activityWorldSchema.safeParse(changed).success).toBe(false);
    const duplicate = activityWorldSchema.parse(structuredClone(source));
    required(duplicate.characters[1]).avatarId = required(
      duplicate.characters[0],
    ).avatarId;
    expect(activityWorldSchema.safeParse(duplicate).success).toBe(false);
  });

  it("allows a draft binding without v1 action IDs but rejects cross-city or wrong-person stories", () => {
    const draft = assignedDraft();
    expect(activityWorldSchema.safeParse(draft).success).toBe(true);
    required(required(draft.characters[0]).assignment).cityId = "newyork";
    expect(activityWorldSchema.safeParse(draft).success).toBe(false);
    const wrongPerson = assignedDraft();
    required(wrongPerson.stories[0]).npcId = required(wrongPerson.characters[1]).id;
    expect(activityWorldSchema.safeParse(wrongPerson).success).toBe(false);
  });

  it("rejects rewriting core traits to make a character fit a place", () => {
    const draft = assignedDraft();
    required(required(draft.characters[0]).assignment).card.hobbies = [
      "coffee tasting",
      "talking to strangers",
    ];
    expect(activityWorldSchema.safeParse(draft).success).toBe(false);
  });

  it("rejects broken branches and causality without a current state", () => {
    const draft = assignedDraft();
    const broken = structuredClone(draft);
    const nodes = required(broken.stories[0]).nodes as {
      id: string;
      choices: { next: string }[];
    }[];
    required(required(nodes.find((node) => node.id === "start")).choices[0]).next =
      "missing";
    expect(activityWorldSchema.safeParse(broken).success).toBe(false);
    required(draft.stories[0]).causality.currentState = "";
    expect(activityWorldSchema.safeParse(draft).success).toBe(false);
  });

  it("keeps canonical hashes independent of object key order", () => {
    expect(canonicalJSON({ z: [1, { b: false, a: null }], a: "伦敦" })).toBe(
      '{"a":"伦敦","z":[1,{"a":null,"b":false}]}',
    );
    expect(contentHash({ a: 1, b: 2 })).toBe(contentHash({ b: 2, a: 1 }));
  });

  it("rejects fictional country codes, contradictory geography and a nonlocal city majority", () => {
    expect(nationalityCountryCodes.size).toBe(249);
    const invented = assignedDraft();
    required(required(invented.characters[0]).assignment).nationalityCountryCodes = [
      "XX",
    ];
    expect(activityWorldSchema.safeParse(invented).success).toBe(false);
    const contradictory = assignedDraft();
    required(required(contradictory.characters[0]).assignment).card.hometown =
      "New York";
    expect(activityWorldSchema.safeParse(contradictory).success).toBe(false);
    const settled = activityWorldFixture();
    for (const person of settled.characters) {
      if (person.assignment?.cityId === "london")
        person.assignment.localConnection = "settled_here";
    }
    expect(activityWorldSchema.safeParse(settled).success).toBe(true);
    const nonlocal = structuredClone(settled);
    for (const person of nonlocal.characters) {
      if (person.assignment?.cityId === "london")
        person.assignment.localConnection = "temporary_stay";
    }
    expect(activityWorldSchema.safeParse(nonlocal).success).toBe(false);
  });
});
