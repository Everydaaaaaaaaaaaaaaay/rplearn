export type DifficultyLevel =
  | "kindergarten"
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

export type LearningGoal =
  | "dailyConversation"
  | "travel"
  | "school"
  | "exam"
  | "studyAbroad"
  | "work"
  | "culture";

export type StudyStage =
  | "primary"
  | "juniorHigh"
  | "seniorHigh"
  | "university"
  | "postgraduate"
  | "working"
  | "other";

export type ProficiencySource = "selfReported" | "placement";

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

export type FirstArrival = Readonly<{
  arrivedAt: string;
  fromRegionId: string;
  id: string;
  toRegionId: string;
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
  hasCompletedProfileSetup: boolean;
  learningGoal: LearningGoal;
  placementCompletedAt: string | null;
  placementScore: number | null;
  proficiencySource: ProficiencySource;
  starterRegionId: string | null;
  studyStage: StudyStage | null;
  unlockedRegionIds: readonly string[];
  updatedAt: string;
  version: number;
}>;

export type UserSnapshot = Readonly<{
  firstArrivals: readonly FirstArrival[];
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
  hasCompletedProfileSetup?: boolean;
  learningGoal?: LearningGoal;
  placementCompletedAt?: string;
  placementScore?: number;
  proficiencySource?: ProficiencySource;
  studyStage?: StudyStage | null;
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
