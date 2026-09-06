import { decimalUnits } from "../modules/access/credit-pricing.js";
import { isBeijingPeak, type PriceBook } from "../modules/access/cost-report.js";
import {
  summarizeSession,
  type LedgerCall,
  type SessionEvidence,
} from "./cost-report.js";

const yuan = (n: bigint): number => Number(n) / 1e9;
export function range(values: number[]) {
  const sorted = [...values].sort((a, b) => a - b);
  if (!sorted.length) return null;
  const middle = Math.floor(sorted.length / 2);
  return {
    n: sorted.length,
    min: sorted[0],
    median:
      sorted.length % 2
        ? sorted[middle]
        : ((sorted[middle - 1] ?? 0) + (sorted[middle] ?? 0)) / 2,
    max: sorted.at(-1),
    mean: sorted.reduce((a, b) => a + b, 0) / sorted.length,
  };
}

// Reprice the observed workload; never pretend these were peak-hour provider calls.
export function peakCost(
  call: LedgerCall,
  book: PriceBook,
  noCache = false,
): bigint | null {
  if (call.status === "released") return 0n;
  if (call.status !== "settled" || !call.usage) return null;
  const row = book.models
    .filter(
      (p) =>
        p.model === call.price.model &&
        Date.parse(p.effectiveFrom) <= Date.parse(call.createdAt),
    )
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
  const usage = call.usage;
  if (
    !row ||
    usage.cacheHitTokens === undefined ||
    usage.cacheMissTokens === undefined ||
    usage.cacheHitTokens + usage.cacheMissTokens !== usage.inputTokens
  )
    return null;
  // CNY per million tokens -> nanoyuan per token.
  const rate = (value: number) => decimalUnits(String(value), 9) / 1_000_000n;
  return (
    BigInt(noCache ? usage.inputTokens : usage.cacheMissTokens) *
      rate(row.inputPerMillion) +
    BigInt(noCache ? 0 : usage.cacheHitTokens) * rate(row.cachedInputPerMillion) +
    BigInt(usage.outputTokens) * rate(row.outputPerMillion)
  );
}

export function observedHeadroom(
  ledger: LedgerCall[],
  settled: (c: LedgerCall) => bigint | null = (c) =>
    c.settledUnits === null ? null : BigInt(c.settledUnits),
  reservation: (c: LedgerCall) => bigint = (c) => BigInt(c.reservedUnits),
) {
  interface Event {
    at: number;
    start: boolean;
    hold: bigint;
    cost: bigint;
  }
  const events: Event[] = [];
  for (const call of ledger) {
    if (!call.completedAt || !["settled", "released"].includes(call.status))
      return null;
    const cost = call.status === "released" ? 0n : settled(call);
    if (cost === null) return null;
    const start = Date.parse(call.createdAt),
      end = Date.parse(call.completedAt);
    if (!Number.isFinite(start) || !Number.isFinite(end) || end < start) return null;
    const hold = reservation(call);
    events.push(
      { at: start, start: true, hold, cost: 0n },
      { at: end, start: false, hold, cost },
    );
  }
  // Millisecond ties conservatively count overlapping reservations.
  events.sort((a, b) => a.at - b.at || Number(b.start) - Number(a.start));
  let spent = 0n,
    held = 0n,
    required = 0n;
  for (const event of events) {
    if (event.start) held += event.hold;
    else {
      held -= event.hold;
      spent += event.cost;
    }
    if (spent + held > required) required = spent + held;
  }
  return yuan(required);
}

export function windowAwareReservation(call: LedgerCall, book: PriceBook): bigint {
  const row = book.models
    .filter(
      (p) =>
        p.model === call.price.model &&
        Date.parse(p.effectiveFrom) <= Date.parse(call.createdAt),
    )
    .sort((a, b) => b.effectiveFrom.localeCompare(a.effectiveFrom))[0];
  const at = Date.parse(call.createdAt);
  if (!row || !Number.isFinite(at)) return BigInt(call.reservedUnits);
  // The shipping reservation expires after five minutes. Include both interval endpoints.
  const couldDispatchAtPeak = Array.from(
    { length: 301 },
    (_, i) => new Date(at + i * 1000),
  ).some(isBeijingPeak);
  const multiplier = decimalUnits(
    String(couldDispatchAtPeak ? 1 : row.offPeakMultiplier),
    6,
  );
  return (BigInt(call.reservedUnits) * multiplier + 999_999n) / 1_000_000n;
}

interface Turn {
  index: number;
  operationIDs: string[];
  reply: string;
  user: string;
  characterName: string;
  remainingCredits?: number;
}
export function outputOmissions(session: SessionEvidence) {
  const tokens = (text: string) =>
    text
      .toLowerCase()
      .replaceAll("’", "'")
      .match(/[\p{L}\p{N}]+(?:'[\p{L}]+)*/gu) ?? [];
  return (session.turns ?? []).flatMap((value) => {
    const turn = value as Turn;
    const calls = (session.nativeCalls ?? []).filter(
      (c) =>
        c.task === "conversation" &&
        c.status === "completed" &&
        turn.operationIDs.includes(c.operationId),
    );
    // Repairs and structured quiz markup need separate review; do not call them clipping.
    if (
      calls.length !== 1 ||
      !calls[0]?.modelOutput ||
      calls[0].modelOutput.includes("<quiz>")
    )
      return [];
    const call = calls[0],
      generated = tokens(call.modelOutput ?? ""),
      delivered = tokens(turn.reply);
    let index = 0;
    for (const token of generated) if (token === delivered[index]) index++;
    if (index !== delivered.length || generated.length <= delivered.length) return [];
    const ledger = session.ledger.find((c) => c.operationId === call.operationId);
    return [
      {
        turn: turn.index,
        operationId: call.operationId,
        generatedWords: generated.length,
        deliveredWords: delivered.length,
        omittedWords: generated.length - delivered.length,
        affectedWholeCallCny: ledger?.settledUnits
          ? yuan(BigInt(ledger.settledUnits))
          : null,
        generated: call.modelOutput,
        delivered: turn.reply,
        interpretation:
          "Exact word subsequence loss detected; inspect meaning. Whole-call cost is not the cost of the omitted words.",
      },
    ];
  });
}

export function analyzeSession(session: SessionEvidence, book: PriceBook) {
  const summary = summarizeSession(session);
  const prices = session.ledger.map((c) => peakCost(c, book));
  const coldPrices = session.ledger.map((c) => peakCost(c, book, true));
  const sumKnown = (values: (bigint | null)[]) =>
    values.some((v) => v === null)
      ? null
      : yuan(values.reduce<bigint>((sum, v) => sum + (v ?? 0n), 0n));
  const turnRows = (session.turns ?? []).map((value) => {
    const turn = value as Turn;
    const calls = session.ledger.filter((c) =>
      turn.operationIDs.includes(c.operationId),
    );
    const main = calls.filter((c) => c.task === "conversation");
    return {
      index: turn.index,
      character: turn.characterName,
      calls: calls.length,
      actualCny: yuan(calls.reduce((a, c) => a + BigInt(c.settledUnits ?? "0"), 0n)),
      peakCny: sumKnown(calls.map((c) => peakCost(c, book))),
      conversationInputTokens: main.reduce(
        (a, c) => a + (c.usage?.inputTokens ?? 0),
        0,
      ),
      conversationCacheTokens: main.reduce(
        (a, c) => a + (c.usage?.cacheHitTokens ?? 0),
        0,
      ),
      userWords: turn.user.trim().split(/\s+/).length,
      replyWords: turn.reply.trim().split(/\s+/).length,
      remainingCredits: turn.remainingCredits,
    };
  });
  const ledgerMismatches = session.ledger
    .filter((c) => {
      if (c.status !== "settled") return false;
      if (
        c.settledUnits === null ||
        !c.usage ||
        !c.price.input ||
        !c.price.cachedInput ||
        !c.price.output
      )
        return true;
      const u = c.usage;
      if (u.cacheMissTokens === undefined || u.cacheHitTokens === undefined)
        return true;
      if (u.cacheMissTokens + u.cacheHitTokens !== u.inputTokens) return true;
      const computed =
        BigInt(u.cacheMissTokens) * BigInt(c.price.input) +
        BigInt(u.cacheHitTokens) * BigInt(c.price.cachedInput) +
        BigInt(u.outputTokens) * BigInt(c.price.output);
      return computed !== BigInt(c.settledUnits);
    })
    .map((c) => c.operationId);
  return {
    ...summary,
    outputOmissions: outputOmissions(session),
    qualityValidatedByRealLearners: false,
    peakSameUsageCny: sumKnown(prices),
    peakNoCacheSameUsageCny: sumKnown(coldPrices),
    peakValuesAreCounterfactual: true,
    windowAwareReservationHeadroomCny: observedHeadroom(
      session.ledger,
      (c) => (c.settledUnits === null ? null : BigInt(c.settledUnits)),
      (c) => windowAwareReservation(c, book),
    ),
    windowAwareReservationIsCounterfactual: true,
    windowAwareReservationTtlSeconds: 300,
    minimumCnyForObservedRequests: observedHeadroom(session.ledger),
    minimumCnyForPeakObservedRequests: observedHeadroom(session.ledger, (c) =>
      peakCost(c, book),
    ),
    // This is a lower bound when a session was cut short; denied requests have no ledger entry.
    headroomCoversFullPlannedJourney:
      summary.status === "completed" &&
      summary.costIsComplete &&
      ledgerMismatches.length === 0,
    maxSingleReservationCny: session.ledger.length
      ? Math.max(...session.ledger.map((c) => yuan(BigInt(c.reservedUnits))))
      : null,
    ledgerMismatches,
    turnRows,
    unassignedToTurnCalls: session.ledger.filter(
      (c) =>
        !(session.turns ?? []).some((v) =>
          (v as Turn).operationIDs.includes(c.operationId),
        ),
    ).length,
  };
}

export function summarizeStratum(sessions: SessionEvidence[], book: PriceBook) {
  const rows = sessions.map((s) => analyzeSession(s, book));
  const valid = rows.filter(
    (s) =>
      s.status === "completed" && s.costIsComplete && s.ledgerMismatches.length === 0,
  );
  return {
    samples: rows.length,
    samplesWithOutputOmissionCandidates: rows.filter(
      (s) => s.outputOmissions.length > 0,
    ).length,
    completionMeasuresWorkflowNotLearningQuality: true,
    completedWithoutGaps: valid.length,
    censoredOrDegraded: rows.length - valid.length,
    plannedTurns: rows.reduce((a, s) => a + s.plannedTurns, 0),
    completedTurns: rows.reduce((a, s) => a + s.completedTurns, 0),
    actualSpendAllSamplesCny: yuan(
      rows.reduce((a, s) => a + BigInt(s.settledNanoyuan), 0n),
    ),
    completeOnlyActualCny: range(valid.map((s) => s.measuredCostCny)),
    completeOnlyPeakCny: range(
      valid.flatMap((s) => (s.peakSameUsageCny === null ? [] : [s.peakSameUsageCny])),
    ),
    completeOnlyPeakNoCacheCny: range(
      valid.flatMap((s) =>
        s.peakNoCacheSameUsageCny === null ? [] : [s.peakNoCacheSameUsageCny],
      ),
    ),
    completeOnlyHeadroomCny: range(
      valid.flatMap((s) =>
        s.minimumCnyForObservedRequests === null
          ? []
          : [s.minimumCnyForObservedRequests],
      ),
    ),
    rows,
    inference:
      "Descriptive synthetic workload repeats; not a representative population or user percentile estimate.",
  };
}

export function planEconomics(input: {
  price: number;
  monthlyModelBudget: number;
  freeUsersPerPayer: number;
  freeCostPerMonth: number;
  otherVariableCosts: number;
  grossRefundTaxBufferRate: number;
  targetContributionRate: number;
}) {
  for (const value of Object.values(input))
    if (!Number.isFinite(value) || value < 0)
      throw new Error("Economics inputs must be finite and nonnegative");
  if (input.grossRefundTaxBufferRate >= 1 || input.targetContributionRate >= 1)
    throw new Error("Rates must be below one");
  const net = input.price * 0.85;
  const buffer = input.price * input.grossRefundTaxBufferRate;
  const freeSubsidy = input.freeUsersPerPayer * input.freeCostPerMonth;
  const contribution =
    net - buffer - input.monthlyModelBudget - freeSubsidy - input.otherVariableCosts;
  const room =
    net * (1 - input.targetContributionRate) -
    buffer -
    freeSubsidy -
    input.otherVariableCosts;
  return {
    ...input,
    channelRate: 0.15,
    netRevenue: net,
    refundTaxBuffer: buffer,
    freeSubsidy,
    contributionBeforeFixedCosts: contribution,
    contributionRateOfNetRevenue: net > 0 ? contribution / net : null,
    maximumModelBudgetAtTargetMargin: Math.max(0, room),
    targetFeasibleBeforeModelCosts: room >= 0,
    breakEvenFreeUsersPerPayer:
      input.freeCostPerMonth > 0
        ? (net - buffer - input.monthlyModelBudget - input.otherVariableCosts) /
          input.freeCostPerMonth
        : null,
    marginIsNotNetProfit: true,
  };
}
