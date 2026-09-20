import { describe, expect, it } from "vitest";
import { publicCard } from "../../../src/modules/npc/card-schema.js";

const card = {
  age: 24, appearance: "Brown hair", background: null, birthday: null,
  gender: "female", hobbies: ["reading"], hometown: null, languages: ["English"],
  name: "Nora", nationality: "British", occupation: "writer",
  personaVoice: { anchorLines: [], boundaries: [], conversationalHabits: [], flaws: [], values: [] },
  personality: "Quiet and kind", regionId: "london", signature: null, speechStyle: null,
};
describe("character reading voice", () => {
  it("preserves explicit casting for shared identities", () => {
    expect(publicCard.parse({ ...card, readingVoice: "F5" }).readingVoice).toBe("F5");
  });
  it("accepts old cards without assigning an undefined field", () => {
    expect(publicCard.parse(card)).not.toHaveProperty("readingVoice");
  });
  it("rejects unknown voice identifiers", () => {
    expect(publicCard.safeParse({ ...card, readingVoice: "F99" }).success).toBe(false);
  });
});
