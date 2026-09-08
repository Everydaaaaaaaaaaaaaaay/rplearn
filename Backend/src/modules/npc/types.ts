export type NpcGender = "female" | "male" | "other";
export type NpcRelationshipStatus = "candidate" | "friend" | "removed";

export type NpcOccupationDomain =
  | "agriculture-nature"
  | "arts-media"
  | "business-finance"
  | "education"
  | "healthcare"
  | "hospitality-food"
  | "public-service"
  | "retired"
  | "science-technology"
  | "service-retail"
  | "skilled-trades"
  | "sports-fitness"
  | "student"
  | "transport-logistics"
  | "other";

export type NpcSocialRole =
  | "caregiver"
  | "connector"
  | "creator"
  | "explorer"
  | "helper"
  | "learner"
  | "mentor"
  | "observer"
  | "organizer"
  | "performer"
  | "problem-solver"
  | "storyteller";

export type NpcInteractionStyle =
  | "analytical"
  | "animated"
  | "blunt"
  | "formal"
  | "gentle"
  | "humorous"
  | "playful"
  | "practical"
  | "reflective"
  | "reserved"
  | "reassuring"
  | "curious";

export type NpcInterestDomain =
  | "arts"
  | "books-learning"
  | "community"
  | "crafts-making"
  | "food-drink"
  | "games"
  | "history-culture"
  | "music"
  | "nature"
  | "photography-film"
  | "sports"
  | "technology"
  | "travel"
  | "wellness";

export type NpcTrait =
  | "adventurous"
  | "ambitious"
  | "calm"
  | "candid"
  | "careful"
  | "curious"
  | "disciplined"
  | "empathetic"
  | "independent"
  | "optimistic"
  | "pragmatic"
  | "reserved"
  | "sociable"
  | "spontaneous"
  | "witty";

export type NpcBackgroundMotif =
  | "belonging"
  | "career-change"
  | "exploration"
  | "family-duty"
  | "fresh-start"
  | "mastery"
  | "migration"
  | "ordinary-life"
  | "recovery"
  | "rivalry"
  | "self-discovery"
  | "service"
  | "tradition";

export type NpcDiversityProfile = Readonly<{
  version: 1;
  occupationDomain: NpcOccupationDomain;
  socialRole: NpcSocialRole;
  interactionStyle: NpcInteractionStyle;
  interestDomains: readonly NpcInterestDomain[];
  traits: readonly NpcTrait[];
  backgroundMotif: NpcBackgroundMotif;
  energy: "low" | "medium" | "high";
  warmth: "reserved" | "balanced" | "warm";
  structure: "spontaneous" | "balanced" | "structured";
}>;

export type NpcDiversityReview = Readonly<{
  decision: "accept" | "revise";
  similarityScore: number;
  dimensions: readonly string[];
  guidance: readonly string[];
}>;

export type PublicNpcCard = Readonly<{
  age: number;
  appearance: string;
  background: string | null;
  birthday: string | null;
  gender: NpcGender;
  hobbies: readonly string[];
  hometown: string | null;
  languages: readonly string[];
  name: string;
  nationality: string;
  occupation: string;
  personaVoice: Readonly<{
    anchorLines: readonly string[];
    boundaries: readonly string[];
    conversationalHabits: readonly string[];
    flaws: readonly string[];
    values: readonly string[];
  }>;
  personality: string;
  regionId: string;
  signature: string | null;
  speechStyle: string | null;
}>;

export type PublicNpc = Readonly<{
  avatar: Readonly<{ id: string; url: string }> | null;
  card: PublicNpcCard;
  createdAt: string;
  id: string;
  travelerId: string;
}>;

export type RegisterPublicNpcInput = Readonly<{
  card: PublicNpcCard;
  diversityProfile?: NpcDiversityProfile | undefined;
  id: string;
  requiredAvatarTags?: readonly string[] | undefined;
  encounterContext?: NpcEncounterContext | undefined;
}>;

export type ReviewNpcDiversityInput = Readonly<{
  card: PublicNpcCard;
  diversityProfile: NpcDiversityProfile;
  encounterContext: NpcEncounterContext;
}>;

export type NpcEncounterContext = Readonly<{
  regionId: string;
  activityId: string;
  category: "culture" | "food" | "outdoors" | "social" | "night";
  language: string;
}>;

export type NpcEncounterSelection = Readonly<{
  npc: PublicNpc | null;
  candidateCount: number;
  reason: "reuse" | "coverage_gap" | "diversity";
}>;

export type AvatarRequirements = Readonly<{
  age: number;
  gender: NpcGender;
  requiredTags: readonly string[];
}>;

export type AvatarProfile = Readonly<{
  ageMin: number;
  ageMax: number;
  gender: NpcGender;
  appearance: string;
  styleVersion: string;
  sha256: string;
}>;

export type LinkNpcRelationshipInput = Readonly<{
  localCharacterId: string;
  status: NpcRelationshipStatus;
}>;
