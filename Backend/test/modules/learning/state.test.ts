import { describe, expect, it } from "vitest";
import { validateLearningPayload } from "../../../src/modules/learning/service.js";
const state = {
  enabled: true,
  ledger: { version: 1, ruleRevision: 4 },
  listening: [],
  pending: [],
};
describe("learning snapshot validation", () => {
  it("accepts the production version and rejects malformed/future state", () => {
    expect(() => validateLearningPayload(JSON.stringify(state))).not.toThrow();
    for (const payload of [
      "null",
      "{",
      "[]",
      JSON.stringify({ ...state, ledger: { version: 2 } }),
      JSON.stringify({ ...state, ledger: { version: 1, ruleRevision: 5 } }),
    ]) {
      expect(() => validateLearningPayload(payload)).toThrow();
    }
  });
  it("bounds UTF8 bytes, not only character count", () => {
    expect(() =>
      validateLearningPayload(
        JSON.stringify({ ...state, notes: "中".repeat(700_000) }),
      ),
    ).toThrow();
  });
});
