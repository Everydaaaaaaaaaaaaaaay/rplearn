import { describe, expect, it } from "vitest";
import {
  encounterWeight,
  weightedIndex,
} from "../../src/modules/npc/encounter-weights.js";

describe("soft encounter weights", () => {
  it("reduces repeat likelihood without excluding recent people and recovers over time", () => {
    expect(encounterWeight(0, 0)).toBe(1);
    expect(encounterWeight(3, 0)).toBeLessThan(encounterWeight(2, 0));
    expect(encounterWeight(3, 14)).toBeGreaterThan(encounterWeight(3, 0));
    expect(encounterWeight(1e9, 0)).toBeGreaterThan(0);
  });
  it("gives every eligible identity a reachable interval including the tail", () => {
    const weights = [1, 0.1, 0.02];
    const hits = [0, 0, 0];
    for (let draw = 0; draw < 10000; draw++) {
      const index = weightedIndex(weights, draw / 10000);
      if (index !== undefined) hits[index] = (hits[index] ?? 0) + 1;
    }
    expect(hits[0]).toBeGreaterThan(hits[1]!);
    expect(hits[1]).toBeGreaterThan(hits[2]!);
    expect(hits[2]).toBeGreaterThan(0);
    expect(weightedIndex([], 0)).toBeUndefined();
    expect(weightedIndex(weights, 1)).toBe(2);
  });
});
