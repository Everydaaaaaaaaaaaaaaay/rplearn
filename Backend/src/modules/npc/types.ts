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
  avatar: Readonly<{
    id: string;
    url: string;
    attribution: string;
    sourceUrl: string | null;
  }> | null;
  card: PublicNpcCard;
  createdAt: string;
  id: string;
  travelerId: string;
}>;

export type RegisterPublicNpcInput = Readonly<{
  card: PublicNpcCard;
  id: string;
}>;

export type LinkNpcRelationshipInput = Readonly<{
  localCharacterId: string;
  status: NpcRelationshipStatus;
}>;
