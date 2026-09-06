import { describe, expect, it } from "vitest";
import {
  estimateCost,
  isBeijingPeak,
  type CostObservation,
  type PriceBook,
} from "../../src/modules/access/cost-report.js";
const book: PriceBook = {
  version: "test",
  source: "https://example.com",
  observedAt: "2026-09-01T00:00:00Z",
  currency: "CNY",
  models: [
    {
      provider: "deepseek",
      model: "flash",
      effectiveFrom: "2026-09-01T00:00:00Z",
      inputPerMillion: 3,
      cachedInputPerMillion: 0.1,
      outputPerMillion: 9,
      offPeakMultiplier: 0.5,
    },
  ],
};
const row: CostObservation = {
  userId: "user",
  task: "conversation",
  plan: "free",
  operationId: null,
  status: "succeeded",
  model: "flash",
  provider: "deepseek",
  configVersion: 1,
  requestedAt: "2026-09-07T01:00:00Z",
  inputTokens: 1000000,
  outputTokens: 1000000,
  cacheHitTokens: 500000,
  cacheMissTokens: 500000,
  providerAttempts: 1,
  latencyMs: 1,
};
describe("versioned cost estimates", () => {
  it("uses Beijing weekdays and exact peak boundaries", () => {
    expect(isBeijingPeak(new Date("2026-09-07T01:00:00Z"))).toBe(true);
    expect(isBeijingPeak(new Date("2026-09-07T04:00:00Z"))).toBe(false);
    expect(isBeijingPeak(new Date("2026-09-06T01:00:00Z"))).toBe(false);
    expect(estimateCost(row, book).cny).toBeCloseTo(10.55);
    expect(
      estimateCost({ ...row, requestedAt: "2026-09-06T01:00:00Z" }, book).cny,
    ).toBeCloseTo(5.275);
  });
  it("never treats missing prices, tokens or retry costs as known zero", () => {
    expect(estimateCost({ ...row, model: "unpriced" }, book).cny).toBeNull();
    expect(estimateCost({ ...row, inputTokens: null }, book).cny).toBeNull();
    expect(
      estimateCost({ ...row, requestedAt: "2026-08-01T00:00:00Z" }, book).cny,
    ).toBeNull();
    expect(estimateCost({ ...row, cacheHitTokens: null }, book).quality).toBe(
      "upper_bound",
    );
    expect(estimateCost({ ...row, providerAttempts: 2 }, book).retryCostUnknown).toBe(
      true,
    );
  });
});
