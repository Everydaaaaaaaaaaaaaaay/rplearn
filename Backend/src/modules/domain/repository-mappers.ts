import type {
  DifficultyLevel,
  LearningGoal,
  ProficiencySource,
  StudyStage,
  Ticket,
  TicketSource,
  TicketType,
  UserProfile,
} from "./types.js";

export type ProfileRow = Readonly<{
  coins: number;
  current_region_id: string;
  difficulty: DifficultyLevel;
  display_name: string;
  experience_points: number;
  friend_slot_limit: number;
  game_level: number;
  has_completed_onboarding: boolean;
  has_completed_profile_setup: boolean;
  learning_goal: LearningGoal;
  placement_completed_at: string | null;
  placement_score: number | null;
  proficiency_source: ProficiencySource;
  starter_region_id: string | null;
  study_stage: StudyStage | null;
  updated_at: string;
  version: number;
}>;

export function mapProfile(
  row: ProfileRow,
  unlockedRegionIds: readonly string[],
): UserProfile & Readonly<{ quizGloballyEnabled: false }> {
  return {
    coins: row.coins,
    currentRegionId: row.current_region_id,
    difficulty: row.difficulty,
    displayName: row.display_name,
    experiencePoints: row.experience_points,
    friendSlotLimit: row.friend_slot_limit,
    gameLevel: row.game_level,
    hasCompletedOnboarding: row.has_completed_onboarding,
    hasCompletedProfileSetup: row.has_completed_profile_setup,
    learningGoal: row.learning_goal,
    placementCompletedAt:
      row.placement_completed_at === null
        ? null
        : new Date(row.placement_completed_at).toISOString(),
    placementScore: row.placement_score,
    proficiencySource: row.proficiency_source,
    // 旧版 iOS 必须解码此字段；仅保留关闭状态的响应兼容，不恢复旧小测业务或数据库字段。
    quizGloballyEnabled: false,
    starterRegionId: row.starter_region_id,
    studyStage: row.study_stage,
    unlockedRegionIds,
    updatedAt: new Date(row.updated_at).toISOString(),
    version: row.version,
  };
}

export function mapTicket(row: {
  country_code: string | null;
  created_at: string;
  id: string;
  source: TicketSource;
  type: TicketType;
}): Ticket {
  return {
    countryCode: row.country_code,
    createdAt: new Date(row.created_at).toISOString(),
    id: row.id,
    source: row.source,
    type: row.type,
  };
}
