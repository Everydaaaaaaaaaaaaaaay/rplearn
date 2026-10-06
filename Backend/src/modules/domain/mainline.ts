const defaultRoute = ["london", "newyork", "melbourne"] as const;
const characterRoutes: Readonly<Record<string, readonly [string, string, string]>> = {
  london: ["london", "newyork", "melbourne"],
  melbourne: ["melbourne", "london", "newyork"],
  newyork: ["newyork", "melbourne", "london"],
};

export function mainlineProgress(input: {
  starterRegionId: string | null;
  hasCompletedOnboarding: boolean;
  completedStoryIds: readonly string[];
  isGuest: boolean;
}) {
  const characters = characterRoutes[input.starterRegionId ?? ""] ?? defaultRoute;
  const route = [characters[0], "capetown", characters[1], characters[2], "singapore"];
  return {
    chapters: route.map((regionId, index) => {
      const storyId = `mainline_${regionId}`;
      const previousStoryId = index === 0 ? null : `mainline_${route[index - 1] ?? ""}`;
      const completed = input.completedStoryIds.includes(storyId);
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
              : null;
      return {
        storyId,
        regionId,
        sequence: index + 1,
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
