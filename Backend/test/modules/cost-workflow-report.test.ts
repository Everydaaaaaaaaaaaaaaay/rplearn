import { describe, it, expect } from "vitest";
import {
  summarizeSession,
  pricingSensitivity,
  type SessionEvidence,
} from "../../src/evaluations/cost-report.js";
const sample: SessionEvidence = {
  id: "a",
  persona: "A",
  plan: "plus",
  plannedTurns: 10,
  completedTurns: 10,
  activeMinutesEstimate: 20,
  activeDaysPerMonthAssumption: 20,
  status: "completed",
  actions: [],
  ledger: [
    {
      operationId: "1",
      task: "conversation",
      status: "settled",
      reservedUnits: "10000000",
      settledUnits: "2500000",
      usage: {
        inputTokens: 100,
        outputTokens: 200,
        cacheHitTokens: 80,
        cacheMissTokens: 20,
      },
      price: { model: "flash", version: "v1" },
      createdAt: "2026-09-06T12:00:00Z",
    },
  ],
};
describe("cost workflow evidence", () => {
  it("keeps integer measured cost separate from assumed monthly demand", () => {
    const r = summarizeSession(sample);
    expect(r.settledNanoyuan).toBe("2500000");
    expect(r.measuredCostCny).toBe(0.0025);
    expect(r.projectedMonthlyCny).toBe(0.05);
    expect(r.minutesAreMeasured).toBe(false);
  });
  it("does not extrapolate censored sessions or erase unknown costs", () => {
    expect(
      summarizeSession({ ...sample, status: "quota_interrupted", completedTurns: 2 })
        .projectedMonthlyCny,
    ).toBeNull();
    const r = summarizeSession({
      ...sample,
      ledger: [
        ...sample.ledger,
        {
          ...sample.ledger[0],
          operationId: "2",
          task: "memory_compress",
          status: "pending",
          reservedUnits: "20000000",
          settledUnits: null,
          usage: null,
          price: { model: "flash", version: "v1" },
          createdAt: "2026-09-06T12:00:01Z",
        },
      ],
    });
    expect(r.unknownCalls).toBe(1);
    expect(r.heldNanoyuan).toBe("20000000");
    expect(r.costIsComplete).toBe(false);
    expect(r.projectedMonthlyCny).toBeNull();
  });
  it("does not hide failed optional actions behind a completed chat count", () => {
    const result = summarizeSession({
      ...sample,
      actions: [{ kind: "translation", status: "failed", milliseconds: 10 }],
    });
    expect(result.status).toBe("completed_with_gaps");
    expect(result.projectedMonthlyCny).toBeNull();
  });
  it("includes auxiliary charges and computes 15 percent channel economics without calling it profit", () => {
    const first = sample.ledger[0];
    if (!first) throw new Error("Missing test call");
    const r = summarizeSession({
      ...sample,
      ledger: [
        {
          ...first,
          task: "coach_review",
        },
      ],
    });
    expect(r.auxiliaryCostCny).toBe(0.0025);
    expect(
      pricingSensitivity(12, 39, 3, 3, 5).contributionBeforeFixedCosts,
    ).toBeCloseTo(7.15);
  });
});
