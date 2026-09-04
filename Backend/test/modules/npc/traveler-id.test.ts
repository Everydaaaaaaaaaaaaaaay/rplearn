import { describe, expect, it } from "vitest";
import {
  isValidTravelerId,
  travelerIdCheckDigit,
} from "../../../src/modules/npc/traveler-id.js";

describe("traveler IDs", () => {
  it("uses a stable Luhn check digit", () => {
    expect(travelerIdCheckDigit("7992739871")).toBe(3);
    expect(isValidTravelerId("79927398713")).toBe(true);
  });

  it("rejects malformed or mistyped IDs", () => {
    expect(isValidTravelerId("79927398714")).toBe(false);
    expect(isValidTravelerId("7992739871A")).toBe(false);
    expect(isValidTravelerId("123")).toBe(false);
  });
});
