export type DifficultyLevel =
  | "primary1"
  | "primary2"
  | "primary3"
  | "primary4"
  | "primary5"
  | "primary6"
  | "junior1"
  | "junior2"
  | "junior3"
  | "senior1"
  | "senior2"
  | "senior3"
  | "undergraduate"
  | "postgraduate"
  | "advanced";

export type TicketType = "universal" | "country";
export type TicketSource =
  "story" | "quest" | "purchase" | "subscription" | "support" | "debug";

export type Ticket = Readonly<{
  countryCode: string | null;
  createdAt: string;
  id: string;
  source: TicketSource;
  type: TicketType;
}>;

export type UserProfile = Readonly<{
  coins: number;
  currentRegionId: string;
  difficulty: DifficultyLevel;
  displayName: string;
  experiencePoints: number;
  friendSlotLimit: number;
  gameLevel: number;
  hasCompletedOnboarding: boolean;
  quizGloballyEnabled: boolean;
  starterRegionId: string | null;
  unlockedRegionIds: readonly string[];
  updatedAt: string;
  version: number;
}>;

export type UserSnapshot = Readonly<{
  profile: UserProfile;
  tickets: readonly Ticket[];
}>;

export type CommandIdentity = Readonly<{
  commandId: string;
  requestHash: string;
  route: string;
}>;

export type ProfilePatch = Readonly<{
  difficulty?: DifficultyLevel;
  displayName?: string;
  expectedVersion: number;
  hasCompletedOnboarding?: boolean;
  quizGloballyEnabled?: boolean;
}>;

export type OnboardingSelection = Readonly<{
  starterRegionId: string;
}>;

export type TravelResult = Readonly<{
  consumedTicketId: string | null;
  fromRegionId: string;
  profileVersion: number;
  toRegionId: string;
  travelId: string;
  traveledAt: string;
  unlockedNow: boolean;
}>;
