import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { activityWorldFixture } from "../helpers/activity-world.js";
import {
  advanceOuting,
  chooseOutingCandidate,
  outingBeats,
} from "../../src/modules/npc/outing-state.js";
import type {
  OutingOperation,
  OutingSnapshot,
} from "../../src/modules/npc/outing-types.js";

const world = activityWorldFixture();
export function snapshotFixture(): OutingSnapshot {
  const person = world.characters[0],
    story = world.stories[0],
    photo = world.media[0],
    place = world.places[0];
  const solitude = place?.solitude[0];
  if (!person || !story || !photo || !place || !solitude)
    throw new Error("Missing fixture");
  return {
    runId: randomUUID(),
    releaseId: world.releaseId,
    cityId: place.cityId,
    placeId: place.id,
    placeTitleZh: place.titleZh,
    createdAt: new Date().toISOString(),
    status: "reserved",
    revision: 0,
    mode: "first_meeting",
    reason: "encounter",
    npc: null,
    story,
    photo,
    solitude,
    nodeId: "start",
    beatIndex: -1,
    choices: [],
  };
}
function readAll(input: OutingSnapshot) {
  let current = input;
  for (
    let index = current.beatIndex + 1;
    index < outingBeats(current).length;
    index += 1
  )
    current = advanceOuting(current, {
      type: "read",
      beatIndex: index,
      operationId: randomUUID(),
      expectedRevision: current.revision,
    });
  return current;
}
function perform(
  input: OutingSnapshot,
  operation: Omit<OutingOperation, "expectedRevision" | "operationId">,
) {
  return advanceOuting(input, {
    ...operation,
    operationId: randomUUID(),
    expectedRevision: input.revision,
  } as OutingOperation);
}

describe("durable outing progression", () => {
  it("requires reading and presentation before choices, then follows only the actual branch", () => {
    const initial = snapshotFixture();
    expect(() => perform(initial, { type: "presented" })).toThrow();
    let current = readAll(initial);
    current = perform(current, { type: "presented" });
    current = advanceOuting(current, {
      type: "choice",
      choiceId: "start:1",
      operationId: randomUUID(),
      expectedRevision: current.revision,
    });
    expect(current.nodeId).toBe("b");
    expect(current.beatIndex).toBe(-1);
    expect(() => perform(current, { type: "complete" })).toThrow();
    current = readAll(current);
    current = advanceOuting(current, {
      type: "choice",
      choiceId: "b:0",
      operationId: randomUUID(),
      expectedRevision: current.revision,
    });
    current = readAll(current);
    current = perform(current, { type: "complete" });
    expect(current.status).toBe("completed");
    expect(current.choices).toEqual(["start:1", "b:0"]);
    expect(initial.choices).toEqual([]);
  });
  it("rejects stale revisions, skipped beats, foreign choices and changes after finishing", () => {
    const initial = snapshotFixture();
    expect(() =>
      advanceOuting(initial, {
        type: "read",
        beatIndex: 2,
        operationId: randomUUID(),
        expectedRevision: 0,
      }),
    ).toThrow();
    expect(() =>
      advanceOuting(initial, {
        type: "abandon",
        operationId: randomUUID(),
        expectedRevision: 1,
      }),
    ).toThrow();
    const shown = perform(readAll(initial), { type: "presented" });
    expect(() =>
      advanceOuting(shown, {
        type: "choice",
        choiceId: "b:0",
        operationId: randomUUID(),
        expectedRevision: shown.revision,
      }),
    ).toThrow();
    const abandoned = perform(shown, { type: "abandon" });
    expect(() => perform(abandoned, { type: "complete" })).toThrow();
  });
  it("does not require two first-meeting decisions for a short reunion or solitude", () => {
    const reunion = readAll({ ...snapshotFixture(), mode: "reunion" });
    expect(
      perform(perform(reunion, { type: "presented" }), { type: "complete" }).status,
    ).toBe("completed");
    const quiet = { ...snapshotFixture(), mode: "solitude" as const };
    expect(
      perform(perform(quiet, { type: "presented" }), { type: "complete" }).status,
    ).toBe("completed");
  });
});

describe("selection within an already eligible place pool", () => {
  const candidates = [
    { id: "new", known: false, weight: 1 },
    { id: "known", known: true, weight: 0.02 },
  ];
  it("allows solitude but guarantees an encounter after two shown quiet visits", () => {
    expect(chooseOutingCandidate(candidates, 0, 0, 0.99, 0, 0)).toBeNull();
    expect(chooseOutingCandidate(candidates, 2, 0, 0.99, 0, 0)?.id).toBe("new");
  });
  it("guarantees discovery after two familiar encounters, without inventing missing people", () => {
    expect(chooseOutingCandidate(candidates, 0, 2, 0, 0.99, 0)?.id).toBe("new");
    expect(
      chooseOutingCandidate(
        [candidates[1]].filter((item) => item !== undefined),
        2,
        2,
        0,
        0,
        0,
      )?.id,
    ).toBe("known");
    expect(chooseOutingCandidate([], 20, 20, 0, 0, 0)).toBeNull();
  });
});
