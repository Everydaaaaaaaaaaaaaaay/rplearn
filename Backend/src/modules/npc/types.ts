export type NpcGender = "female" | "male" | "other";
export type NpcRelationshipStatus = "candidate" | "friend" | "removed";

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
  id: string;
  requiredAvatarTags?: readonly string[] | undefined;
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
