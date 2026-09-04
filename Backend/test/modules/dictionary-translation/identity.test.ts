import { describe, expect, it } from "vitest";
import { createDictionaryExampleIdentity } from "../../../src/modules/dictionary-translation/identity.js";

const base = {
  candidateMeaningsZhHans: [],
  dictionary: { source: "wordnet", version: "3.1" },
  lemma: "mate",
  partOfSpeech: "noun",
  sentence: "He is my best mate.",
} as const;

describe("dictionary translation identity", () => {
  it("includes the English sense definition in the stable sense fingerprint", () => {
    const friend = createDictionaryExampleIdentity({
      ...base,
      senseDefinitionEn: "a close friend or companion",
    });
    const partner = createDictionaryExampleIdentity({
      ...base,
      senseDefinitionEn: "a person's husband, wife, or partner",
    });
    expect(friend.senseFingerprint).not.toBe(partner.senseFingerprint);
    expect(friend.sourceKey).not.toBe(partner.sourceKey);
    expect(friend.senseDefinitionEn).toBe("a close friend or companion");
  });
});
