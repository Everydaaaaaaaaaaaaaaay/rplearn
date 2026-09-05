import type { AvatarMetadata } from "../../src/modules/npc/avatar-catalog.js";
import type { PublicNpcCard } from "../../src/modules/npc/types.js";

// Synthetic test metadata. No image is downloaded or licensed by this fixture.
export const avatarMetadata: AvatarMetadata = {
  cultures: ["badminton"],
  interestIndependent: false,
  subjects: ["羽毛球"],
  aesthetics: ["minimalist"],
  expressions: ["quiet"],
  regions: ["Japan"],
  eras: ["contemporary"],
  source: {
    kind: "commissioned",
    pageUrl: "https://example.com/test-art",
    creator: "Test artist",
    license: "Test-only permission",
    licenseUrl: "https://example.com/test-license",
    evidence: "Synthetic test fixture, not a publishable asset",
    attribution: "Test artist",
    attributionRequired: true,
    reviewedBy: "test",
    reviewedAt: "2026-09-05T00:00:00Z",
    commercialUse: true,
    derivatives: true,
    distribution: true,
  },
  quality: {
    squareCropChecked: true,
    smallSizeChecked: true,
    culturalAccuracyChecked: true,
    safetyChecked: true,
    similarityChecked: true,
  },
};
export const npcCard: PublicNpcCard = {
  age: 29,
  appearance: "Short dark hair",
  background: null,
  birthday: null,
  gender: "female",
  hobbies: ["羽毛球", "日本文化"],
  hometown: null,
  languages: ["English"],
  name: "Nora",
  nationality: "British",
  occupation: "Teacher",
  personaVoice: {
    anchorLines: [],
    boundaries: [],
    conversationalHabits: [],
    flaws: [],
    values: [],
  },
  personality: "低调、安静",
  regionId: "london",
  signature: null,
  speechStyle: null,
};
