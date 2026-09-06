import { describe, expect, it } from "vitest";
import {
  observedHeadroom,
  outputOmissions,
  windowAwareReservation,
  peakCost,
  planEconomics,
  summarizeStratum,
} from "../../src/evaluations/cost-study.js";
import type { LedgerCall, SessionEvidence } from "../../src/evaluations/cost-report.js";
import type { PriceBook } from "../../src/modules/access/cost-report.js";
const book: PriceBook = {
  version: "v1",
  source: "https://example.com/pricing",
  observedAt: "2026-09-06T00:00:00Z",
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
const call: LedgerCall = {
  operationId: "a",
  task: "conversation",
  status: "settled",
  reservedUnits: "50000000",
  settledUnits: "12000000",
  usage: {
    inputTokens: 1000,
    outputTokens: 100,
    cacheHitTokens: 800,
    cacheMissTokens: 200,
  },
  price: {
    model: "flash",
    version: "v1",
    input: "1500",
    cachedInput: "50",
    output: "116600",
  },
  createdAt: "2026-09-06T01:00:00Z",
  completedAt: "2026-09-06T01:00:01Z",
};
const session: SessionEvidence = {
  id: "a-r1",
  scenarioId: "a",
  persona: "A",
  plan: "pro",
  plannedTurns: 10,
  completedTurns: 10,
  activeMinutesEstimate: 20,
  activeDaysPerMonthAssumption: 20,
  status: "completed",
  actions: [],
  ledger: [call],
};
describe("decision evidence", () => {
  it("detects content discarded after billing without equating whole-call cost to waste", () => {
    const result = outputOmissions({
      ...session,
      nativeCalls: [
        {
          operationId: "a",
          task: "conversation",
          status: "completed",
          modelOutput:
            "Release a smaller version first, then test it properly. Does that help?",
        },
      ],
      turns: [
        {
          index: 1,
          operationIDs: ["a"],
          reply: "Release a smaller version first, Does that help?",
          user: "How should I explain this?",
          characterName: "A",
        },
      ],
    });
    expect(result).toHaveLength(1);
    expect(result[0]?.omittedWords).toBe(4);
    expect(result[0]?.affectedWholeCallCny).toBe(0.012);
  });
  it("keeps peak headroom whenever a dispatch can cross the tariff boundary", () => {
    expect(windowAwareReservation(call, book)).toBe(25_000_000n);
    expect(
      windowAwareReservation({ ...call, createdAt: "2026-09-07T00:58:00Z" }, book),
    ).toBe(50_000_000n);
    expect(
      windowAwareReservation({ ...call, createdAt: "2026-09-07T00:54:00Z" }, book),
    ).toBe(25_000_000n);
  });
  it("counts concurrent reservations as a usability requirement, not a charge", () => {
    const second = {
      ...call,
      operationId: "b",
      reservedUnits: "40000000",
      settledUnits: "5000000",
      createdAt: "2026-09-06T01:00:00.500Z",
      completedAt: "2026-09-06T01:00:02Z",
    };
    expect(observedHeadroom([call, second])).toBe(0.09);
    expect(
      observedHeadroom([call, { ...second, createdAt: "2026-09-06T01:00:01.500Z" }]),
    ).toBe(0.052);
    expect(
      observedHeadroom([{ ...call, status: "pending", settledUnits: null }]),
    ).toBeNull();
  });
  it("separates peak repricing and hypothetical cache removal from observed costs", () => {
    expect(peakCost(call, book)).toBe(1580000n);
    expect(peakCost(call, book, true)).toBe(3900000n);
    expect(
      peakCost({ ...call, usage: { inputTokens: 1000, outputTokens: 100 } }, book),
    ).toBeNull();
  });
  it("includes censored spending but excludes it from complete-session statistics", () => {
    const group = summarizeStratum(
      [
        session,
        { ...session, id: "a-r2", status: "quota_interrupted", completedTurns: 2 },
      ],
      book,
    );
    expect(group.samples).toBe(2);
    expect(group.completedWithoutGaps).toBe(1);
    expect(group.actualSpendAllSamplesCny).toBe(0.024);
    expect(group.completeOnlyActualCny?.n).toBe(1);
    expect(group.rows[1]?.headroomCoversFullPlannedJourney).toBe(false);
  });
  it("detects ledger inconsistencies before admitting a sample into pricing analysis", () => {
    const bad = {
      ...call,
      price: { ...call.price, input: "1500", cachedInput: "50", output: "4500" },
    };
    const group = summarizeStratum([{ ...session, ledger: [bad] }], book);
    expect(group.rows[0]?.ledgerMismatches).toEqual(["a"]);
    expect(group.completedWithoutGaps).toBe(0);
    expect(group.rows[0]?.headroomCoversFullPlannedJourney).toBe(false);
    const missing = summarizeStratum(
      [{ ...session, ledger: [{ ...call, price: { model: "flash", version: "v1" } }] }],
      book,
    );
    expect(missing.completedWithoutGaps).toBe(0);
    expect(missing.rows[0]?.ledgerMismatches).toEqual(["a"]);
  });
  it("uses full budget, subsidy and buffers rather than assuming profitable underuse", () => {
    const result = planEconomics({
      price: 39,
      monthlyModelBudget: 12,
      freeUsersPerPayer: 3,
      freeCostPerMonth: 1,
      otherVariableCosts: 5,
      grossRefundTaxBufferRate: 0.05,
      targetContributionRate: 0.35,
    });
    expect(result.netRevenue).toBeCloseTo(33.15);
    expect(result.contributionBeforeFixedCosts).toBeCloseTo(11.2);
    expect(result.maximumModelBudgetAtTargetMargin).toBeCloseTo(11.5975);
    expect(result.contributionRateOfNetRevenue).toBeLessThan(0.35);
    expect(() => planEconomics({ ...result, price: Number.NaN })).toThrow();
  });
});
