/** Recency changes likelihood, never eligibility. Mirrors the local reunion policy. */
export function encounterWeight(encounters: number, daysSinceSeen: number): number {
  const recent = Math.exp(-Math.max(0, daysSinceSeen) / 7);
  return Math.max(0.02, 1 / (1 + Math.max(0, encounters) * recent));
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
