/** Recency changes likelihood, never eligibility. Mirrors the local reunion policy. */
export function encounterWeight(encounters: number, daysSinceSeen: number): number {
  const recent = Math.exp(-Math.max(0, daysSinceSeen) / 7);
  return Math.max(0.02, 1 / (1 + Math.max(0, encounters) * recent));
}

/** Reserve 40% of selection mass for uniform exploration within the eligible pool.
 * Each candidate therefore has probability >= 0.4 / N, even after many meetings.
 * Remaining mass retains scene-fit/recency preferences; this never creates eligibility.
 */
export function balancedEncounterWeights(weights: readonly number[]): number[] {
  if (weights.length === 0) return [];
  const safe = weights.map((weight) =>
    Number.isFinite(weight) ? Math.max(0.02, Math.min(weight, 1e6)) : 0.02,
  );
  const mean = safe.reduce((sum, weight) => sum + weight, 0) / safe.length;
  return safe.map((weight) => 0.6 * weight + 0.4 * mean);
}

export function weightedIndex(
  weights: readonly number[],
  roll: number,
): number | undefined {
  if (!weights.length) return undefined;
  const safe = weights.map((weight) =>
    Number.isFinite(weight) ? Math.max(0.02, weight) : 0.02,
  );
  let remaining =
    Math.min(Math.max(roll, 0), 1 - Number.EPSILON) *
    safe.reduce((sum, weight) => sum + weight, 0);
  for (const [index, weight] of safe.entries()) {
    remaining -= weight;
    if (remaining < 0) return index;
  }
  return safe.length - 1;
}
