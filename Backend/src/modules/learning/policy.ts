import { levelKeys, type LearningLevel } from "./content.js";

export const learningPolicy = Object.freeze({
  version: 1,
  characterThreshold: 500,
  pointsPerQuestion: 1,
  pointsPerStar: 60,
  starsPerLevel: 9,
});

const segmenter = new Intl.Segmenter("en", { granularity: "grapheme" });
/** 正文按字素计数；空白先移除，不按 UTF-16 单元或字节计数。 */
export function countChatCharacters(text: string): number {
  return Array.from(segmenter.segment(text.replace(/\s/gu, ""))).length;
}

export function levelProgress(points: number) {
  if (!Number.isSafeInteger(points) || points < 0)
    throw new Error("学习点数必须是非负安全整数。");
  const max = learningPolicy.pointsPerStar * learningPolicy.starsPerLevel;
  const displayPoints = Math.min(points, max);
  return {
    points,
    displayPoints,
    targetPoints: max,
    stars: Math.min(
      learningPolicy.starsPerLevel,
      Math.floor(points / learningPolicy.pointsPerStar),
    ),
    currentStarPoints:
      displayPoints === max
        ? learningPolicy.pointsPerStar
        : points % learningPolicy.pointsPerStar,
    pointsPerStar: learningPolicy.pointsPerStar,
  };
}

export function nextLearningLevel(level: LearningLevel): LearningLevel | null {
  return levelKeys[levelKeys.indexOf(level) + 1] ?? null;
}

export function promotionEligibility(input: {
  level: LearningLevel;
  points: number;
  coveredGoalIds: readonly string[];
  requiredGoalIds: readonly string[];
  hasTransferUnit: boolean;
  nextLevelAvailable: boolean;
}) {
  const missingGoalIds = input.requiredGoalIds.filter(
    (id) => !input.coveredGoalIds.includes(id),
  );
  return {
    nextLevel: nextLearningLevel(input.level),
    missingGoalIds,
    ready:
      input.requiredGoalIds.length > 0 &&
      missingGoalIds.length === 0 &&
      input.hasTransferUnit &&
      input.points >= learningPolicy.pointsPerStar * learningPolicy.starsPerLevel &&
      input.nextLevelAvailable &&
      nextLearningLevel(input.level) !== null,
  };
}
