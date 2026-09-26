import type { TransactionSql } from "postgres";

/** 只接受学习系统记录的实得里程碑，档案中自选的年级不参与解锁。 */
export type EarnedStarsReader = (
  sql: TransactionSql,
  userId: string,
) => Promise<number>;

const defaultRoute = ["london", "newyork", "melbourne"] as const;
const characterRoutes: Readonly<Record<string, readonly [string, string, string]>> = {
  london: ["london", "newyork", "melbourne"],
  melbourne: ["melbourne", "london", "newyork"],
  newyork: ["newyork", "melbourne", "london"],
};
const thresholds = [0, 3, 9, 18, 27] as const;

export function mainlineProgress(input: {
  starterRegionId: string | null;
  hasCompletedOnboarding: boolean;
  earnedStars: number;
  completedStoryIds: readonly string[];
  isGuest: boolean;
}) {
  const characters = characterRoutes[input.starterRegionId ?? ""] ?? defaultRoute;
  const route = [characters[0], "capetown", characters[1], characters[2], "singapore"];
  return {
    earnedStars: input.earnedStars,
    chapters: route.map((regionId, index) => {
      const storyId = `mainline_${regionId}`;
      const previousStoryId = index === 0 ? null : `mainline_${route[index - 1] ?? ""}`;
      const requiredStars = thresholds[index] ?? 27;
      const completed = input.completedStoryIds.includes(storyId);
      const missingStars = Math.max(0, requiredStars - input.earnedStars);
      const previousCompleted =
        previousStoryId === null || input.completedStoryIds.includes(previousStoryId);
      const lockReason = completed
        ? null
        : !input.hasCompletedOnboarding
          ? "onboarding"
          : input.isGuest && index > 0
            ? "login"
            : !previousCompleted
              ? "previousChapter"
              : missingStars > 0
                ? "stars"
                : null;
      return {
        storyId,
        regionId,
        sequence: index + 1,
        requiredStars,
        missingStars,
        previousStoryId,
        state: completed
          ? ("completed" as const)
          : lockReason === null
            ? ("available" as const)
            : ("locked" as const),
        lockReason,
      };
    }),
  };
}
export type MainlineProgress = ReturnType<typeof mainlineProgress>;
