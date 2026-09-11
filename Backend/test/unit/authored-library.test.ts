import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  authoredLibrarySchema,
  authoredStorySchema,
} from "../../src/modules/npc/authored-library-repository.js";
import { travelerIdCheckDigit } from "../../src/modules/npc/traveler-id.js";

const slots = JSON.parse(
  readFileSync(
    new URL("../../../Content/NPCLibrary/2026-09-11/slots.json", import.meta.url),
    "utf8",
  ),
) as {
  avatarId: string;
  avatarSHA256: string;
  age: number;
  gender: string;
  appearance: string;
  regionId: string;
  actionId: string;
}[];
const pilot = JSON.parse(
  readFileSync(
    new URL("../../../Content/NPCPilot/2026-09-11/pilot-01.json", import.meta.url),
    "utf8",
  ),
) as { card: Record<string, unknown>; story: Record<string, unknown> };
const manifest = () => ({
  version: 1,
  libraryVersion: "test",
  entries: slots.map((slot, i) => {
    const body = String(i + 1).padStart(10, "0");
    return {
      id: slot.avatarId,
      travelerId: body + String(travelerIdCheckDigit(body)),
      avatarId: slot.avatarId,
      avatarSHA256: slot.avatarSHA256,
      card: {
        ...pilot.card,
        name: `Fixture ${String(i)}`,
        age: slot.age,
        gender: slot.gender,
        appearance: slot.appearance,
        regionId: slot.regionId,
      },
      summaryZh: "Test only",
      story: { ...pilot.story, actionId: slot.actionId },
      reunion: {
        titleZh: "再次相遇",
        beats: (pilot.story.nodes as { beats: unknown[] }[])[0]?.beats,
      },
    };
  }),
});

describe("authored roster admission", () => {
  it("accepts actual slot coverage and rejects a missing reachable city/action", () => {
    const value = manifest();
    expect(authoredLibrarySchema.safeParse(value).success).toBe(true);
    const solo = value.entries.find(
      (entry) =>
        value.entries.filter(
          (other) =>
            other.card.regionId === entry.card.regionId &&
            other.story.actionId === entry.story.actionId,
        ).length === 1,
    );
    if (!solo) throw Error("Missing singleton fixture");
    solo.story.actionId =
      solo.story.actionId === "park-route" ? "park-seat" : "park-route";
    expect(authoredLibrarySchema.safeParse(value).success).toBe(false);
  });
  it("rejects duplicate portrait allocation and broken story edges", () => {
    const value = manifest();
    const first = value.entries[0],
      second = value.entries[1];
    if (!first || !second) throw Error("Missing fixtures");
    second.avatarId = first.avatarId;
    expect(authoredLibrarySchema.safeParse(value).success).toBe(false);
    const story = authoredStorySchema.parse({ ...pilot.story, actionId: "park-route" });
    const start = story.nodes.find((node) => node.id === "start");
    if (!start?.choices[0]) throw Error("Missing start");
    start.choices[0].next = "missing";
    expect(authoredStorySchema.safeParse(story).success).toBe(false);
  });
});
