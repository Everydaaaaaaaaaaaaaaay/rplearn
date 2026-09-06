import { z } from "zod";
export const priceBookSchema = z.object({
  version: z.string(),
  source: z.url(),
  observedAt: z.iso.datetime(),
  currency: z.literal("CNY"),
  models: z.array(
    z.object({
      provider: z.string(),
      model: z.string(),
      effectiveFrom: z.iso.datetime(),
      inputPerMillion: z.number().nonnegative(),
      cachedInputPerMillion: z.number().nonnegative(),
      outputPerMillion: z.number().nonnegative(),
      offPeakMultiplier: z.number().positive().max(1),
    }),
  ),
});
export type PriceBook = z.infer<typeof priceBookSchema>;
export interface CostObservation {
  userId: string;
  task: string;
  plan: string;
  operationId: string | null;
  status: string;
  model: string;
  provider: string;
  configVersion: number;
  requestedAt: string;
  inputTokens: number | null;
  outputTokens: number | null;
  cacheHitTokens: number | null;
  cacheMissTokens: number | null;
  providerAttempts: number;
  latencyMs: number | null;
}
export function isBeijingPeak(instant: Date): boolean {
  const local = new Date(instant.getTime() + 8 * 3600_000),
    day = local.getUTCDay();
  const minute = local.getUTCHours() * 60 + local.getUTCMinutes();
  return (
    day >= 1 &&
    day <= 5 &&
    ((minute >= 540 && minute < 720) || (minute >= 840 && minute < 1080))
  );
}
export function estimateCost(
  row: CostObservation,
  book: PriceBook,
): {
  cny: number | null;
  quality: "unknown" | "upper_bound" | "estimated";
  retryCostUnknown: boolean;
} {
  const prices = book.models
    .filter(
      (p) =>
        p.model === row.model &&
        p.provider === row.provider &&
        p.effectiveFrom <= row.requestedAt,
    )
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom));
  const price = prices[0];
  const retryCostUnknown = row.providerAttempts > 1 || row.status !== "succeeded";
  if (!price || row.inputTokens === null || row.outputTokens === null)
    return { cny: null, quality: "unknown", retryCostUnknown };
  const knownCache =
    row.cacheHitTokens !== null && row.cacheHitTokens <= row.inputTokens;
  const hit = knownCache ? (row.cacheHitTokens ?? 0) : 0;
  const multiplier = isBeijingPeak(new Date(row.requestedAt))
    ? 1
    : price.offPeakMultiplier;
  return {
    cny:
      ((hit * price.cachedInputPerMillion +
        (row.inputTokens - hit) * price.inputPerMillion +
        row.outputTokens * price.outputPerMillion) *
        multiplier) /
      1_000_000,
    quality: knownCache ? "estimated" : "upper_bound",
    retryCostUnknown,
  };
}
function percentile(values: number[], p: number): number | null {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil(p * sorted.length) - 1)] ?? null;
}
export function buildCostReport(rows: CostObservation[], book: PriceBook) {
  const groups = new Map<string, CostObservation[]>();
  for (const row of rows) {
    const key = `${row.plan}/${row.task}/${row.provider}/${row.model}/v${String(row.configVersion)}`;
    groups.set(key, [...(groups.get(key) ?? []), row]);
  }
  return {
    priceVersion: book.version,
    priceSource: book.source,
    currency: book.currency,
    requests: rows.length,
    note: "API-token estimates, not invoices. Unknown attempts, infrastructure, storage and taxes are excluded; missing values are never zero.",
    groups: [...groups].map(([scenario, requests]) => {
      const estimates = requests.map((row) => ({ row, ...estimateCost(row, book) }));
      const values = estimates.flatMap((x) => (x.cny === null ? [] : [x.cny]));
      const perUser = new Map<string, number>();
      for (const x of estimates)
        if (x.cny !== null)
          perUser.set(x.row.userId, (perUser.get(x.row.userId) ?? 0) + x.cny);
      return {
        scenario,
        requests: requests.length,
        users: new Set(requests.map((r) => r.userId)).size,
        knownCostCny: values.length ? values.reduce((a, b) => a + b, 0) : null,
        unknownCostRequests: estimates.filter((x) => x.cny === null).length,
        cacheUpperBoundRequests: estimates.filter((x) => x.quality === "upper_bound")
          .length,
        unknownRetryCosts: estimates.filter((x) => x.retryCostUnknown).length,
        providerAttempts: requests.reduce((sum, r) => sum + r.providerAttempts, 0),
        perRequestCny: {
          p50: percentile(values, 0.5),
          p90: percentile(values, 0.9),
          p95: percentile(values, 0.95),
        },
        perObservedUserCny: {
          p50: percentile([...perUser.values()], 0.5),
          p90: percentile([...perUser.values()], 0.9),
          p95: percentile([...perUser.values()], 0.95),
        },
      };
    }),
  };
}
