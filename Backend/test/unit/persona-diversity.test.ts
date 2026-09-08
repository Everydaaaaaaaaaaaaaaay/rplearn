import { describe, expect, it } from "vitest";
import {
  deriveDiversityProfile,
  personaSignature,
  reconcileDiversityProfile,
  reviewPersonaDiversity,
} from "../../src/modules/npc/persona-diversity.js";
import type {
  NpcDiversityProfile,
  PublicNpcCard,
} from "../../src/modules/npc/types.js";

function card(overrides: Partial<PublicNpcCard> = {}): PublicNpcCard {
  return {
    age: 31,
    appearance: "Provisional portrait",
    background: "Runs a flower stall and is trying to master rare orchids.",
    birthday: "04-19",
    gender: "female",
    hobbies: ["园艺", "骑行", "看老电影"],
    hometown: "Brighton",
    languages: ["English"],
    name: "Poppy Hale",
    nationality: "British",
    occupation: "florist",
    personaVoice: {
      anchorLines: ["Give me a second, love."],
      boundaries: ["does not mock sincere questions"],
      conversationalHabits: ["notices small details", "uses gentle humour"],
      flaws: ["sometimes forgetful"],
      values: ["kindness", "craft"],
    },
    personality: "warm, observant and a little forgetful",
    regionId: "london",
    signature: "Flowers remember the weather.",
    speechStyle: "soft, quick and gently humorous",
    ...overrides,
  };
}

const florist: NpcDiversityProfile = {
  version: 1,
  occupationDomain: "service-retail",
  socialRole: "creator",
  interactionStyle: "gentle",
  interestDomains: ["nature", "crafts-making", "photography-film"],
  traits: ["empathetic", "careful", "calm"],
  backgroundMotif: "mastery",
  energy: "medium",
  warmth: "warm",
  structure: "balanced",
};

describe("NPC persona diversity", () => {
  it("rejects an identical narrative even when identity cosmetics change", () => {
    const original = card();
    const renamed = card({
      name: "A Different Name",
      appearance: "Entirely different portrait",
      birthday: "10-02",
    });
    expect(personaSignature(renamed)).toBe(personaSignature(original));
    expect(
      reviewPersonaDiversity({ card: renamed, profile: florist }, [
        { card: original, profile: florist },
      ]),
    ).toMatchObject({ decision: "revise", similarityScore: 100 });
  });

  it("rejects the same composite role despite surface-level rewrites", () => {
    const rewrite = card({
      name: "Mara Bell",
      occupation: "weekend plant seller",
      background:
        "Keeps a market plant booth while learning difficult grafting techniques.",
      personality: "patient, warm and attentive, but occasionally absent-minded",
    });
    const review = reviewPersonaDiversity({ card: rewrite, profile: florist }, [
      { card: card(), profile: florist },
    ]);
    expect(review.decision).toBe("revise");
    expect(review.dimensions).toContain("occupation-domain");
    expect(review.guidance.length).toBeGreaterThanOrEqual(2);
  });

  it("allows a shared hobby when the person's function and voice are different", () => {
    const mechanicProfile: NpcDiversityProfile = {
      version: 1,
      occupationDomain: "skilled-trades",
      socialRole: "problem-solver",
      interactionStyle: "blunt",
      interestDomains: ["nature", "technology"],
      traits: ["candid", "pragmatic", "independent"],
      backgroundMotif: "fresh-start",
      energy: "high",
      warmth: "balanced",
      structure: "structured",
    };
    const mechanic = card({
      name: "Dev Singh",
      age: 52,
      occupation: "bicycle mechanic",
      hobbies: ["园艺", "修复老收音机"],
      personality: "blunt, energetic and practical",
      speechStyle: "short technical answers",
      background: "Reopened a repair shop after changing careers.",
    });
    expect(
      reviewPersonaDiversity({ card: mechanic, profile: mechanicProfile }, [
        { card: card(), profile: florist },
      ]).decision,
    ).toBe("accept");
  });

  it("does not hide a risky lexical neighbor behind a higher harmless structured score", () => {
    const twoCoreProfile: NpcDiversityProfile = {
      ...florist,
      interactionStyle: "formal",
      backgroundMotif: "migration",
    };
    const lexicalNeighborProfile: NpcDiversityProfile = {
      ...twoCoreProfile,
      traits: ["empathetic", "witty"],
    };
    const lexicalNeighbor = card({
      name: "Mara Bell",
      background:
        "Runs the flower stall and works patiently to master unusual orchids.",
    });
    const unrelatedText = card({
      name: "Tess Ward",
      occupation: "unclassified fixture",
      hobbies: ["制作风筝"],
      personality: "methodical and distant",
      speechStyle: "long formal explanations",
      background: "Recently moved and is rebuilding a quiet daily routine.",
      personaVoice: {
        anchorLines: ["That is the documented result."],
        boundaries: ["keeps work and private life separate"],
        conversationalHabits: ["defines terms before answering"],
        flaws: ["overexplains"],
        values: ["accuracy"],
      },
    });
    const review = reviewPersonaDiversity({ card: card(), profile: florist }, [
      { card: unrelatedText, profile: twoCoreProfile },
      { card: lexicalNeighbor, profile: lexicalNeighborProfile },
    ]);
    expect(review.decision).toBe("revise");
  });

  it("classifies legacy cards deterministically", () => {
    const legacy = deriveDiversityProfile(
      card({
        occupation: "bicycle mechanic",
        personality: "quiet, practical and precise",
        hobbies: ["修复老收音机", "骑行"],
      }),
    );
    expect(legacy.occupationDomain).toBe("skilled-trades");
    expect(legacy.interactionStyle).toBe("reserved");
    expect(legacy.interestDomains).toContain("sports");
  });

  it("does not let a contradictory submitted label bypass an obvious occupation", () => {
    const reconciled = reconcileDiversityProfile(
      card({ occupation: "bicycle mechanic", personality: "quiet and practical" }),
      florist,
    );
    expect(reconciled.occupationDomain).toBe("skilled-trades");
    expect(reconciled.interactionStyle).toBe("reserved");
  });
});
