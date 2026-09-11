import { describe, expect, it } from "vitest";
import {
  balancedEncounterWeights,
  encounterWeight,
  weightedIndex,
} from "../../src/modules/npc/encounter-weights.js";

describe("encounter exploration probability", () => {
  it("bounds every eligible person's probability under extreme repeat histories", () => {
    for (const size of [1, 2, 14, 200]) {
      const weights = balancedEncounterWeights(
        Array.from({ length: size }, (_, i) => encounterWeight(i === 0 ? 0 : 1e9, 0)),
      );
      const sum = weights.reduce((a, b) => a + b, 0);
      for (const weight of weights)
        expect(weight / sum).toBeGreaterThanOrEqual(0.4 / size - 1e-12);
    }
  });

  it("samples all 200 identities while preserving unequal likelihoods", () => {
    const weights = balancedEncounterWeights(
      Array.from({ length: 200 }, (_, i) => (i === 0 ? 1 : 0.02)),
    );
    const hits = Array.from({ length: 200 }, () => 0);
    for (let draw = 0; draw < 100_000; draw++) {
      const index = weightedIndex(weights, (draw + 0.5) / 100_000);
      if (index !== undefined) hits[index] = (hits[index] ?? 0) + 1;
    }
    expect(Math.min(...hits)).toBeGreaterThanOrEqual(200);
    expect(hits[0]).toBeGreaterThan(hits[1] ?? 0);
    expect(balancedEncounterWeights([])).toEqual([]);
  });
});
