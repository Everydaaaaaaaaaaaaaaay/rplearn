import { v5 as uuidv5 } from "uuid";
import type { TransactionSql } from "postgres";
import type { LearningContextReader, PromotionProfile } from "./context.js";
import type { LearningLevel } from "./content.js";
import { learningPolicy, nextLearningLevel } from "./policy.js";

export type AutomaticPromotion = Readonly<{
  fromLevel: LearningLevel;
  toLevel: LearningLevel;
  profileVersion: number;
}>;

/** Only called by writable sessions holding the account learning transaction lock. */
export async function automaticallyPromote(
  sql: TransactionSql,
  userId: string,
  context: LearningContextReader | undefined,
): Promise<{ profile: PromotionProfile; promotion: AutomaticPromotion | null } | null> {
  if (!context?.promotionProfile || !context.promoteProfile) return null;
  // Take the domain lock before any shared profile row lock, matching domain writers.
  let profile = await context.promotionProfile(sql, userId);
  const fromLevel = profile.difficulty;
  for (
    let next = nextLearningLevel(profile.difficulty);
    next;
    next = nextLearningLevel(profile.difficulty)
  ) {
    const [progress] = await sql<{ points: number }[]>`
      select points from app.learning_level_progress where user_id=${userId} and level_key=${profile.difficulty}`;
    if (
      (progress?.points ?? 0) <
      learningPolicy.pointsPerStar * learningPolicy.starsPerLevel
    )
      break;
    const requestId = uuidv5(
      `lingotrip:learning:auto-promotion:${userId}:${profile.difficulty}:${String(profile.version)}`,
      uuidv5.URL,
    );
    profile = await context.promoteProfile(
      sql,
      userId,
      requestId,
      profile.difficulty,
      next,
      profile.version,
    );
  }
  return {
    profile,
    promotion:
      profile.difficulty === fromLevel
        ? null
        : {
            fromLevel,
            toLevel: profile.difficulty,
            profileVersion: profile.version,
          },
  };
}
