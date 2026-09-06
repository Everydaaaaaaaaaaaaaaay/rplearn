export interface LedgerCall {
  operationId: string;
  task: string;
  status: string;
  reservedUnits: string;
  settledUnits: string | null;
  usage: {
    inputTokens: number;
    outputTokens: number;
    cacheHitTokens?: number;
    cacheMissTokens?: number;
  } | null;
  price: { model: string; version: string; input?: string; output?: string };
  createdAt: string;
  routeConfigVersion?: number | null;
  providerAttempts?: number | null;
  latencyMs?: number | null;
  providerRequestId?: string | null;
}
export interface SessionEvidence {
  id: string;
  persona: string;
  plan: string;
  plannedTurns: number;
  completedTurns: number;
  activeMinutesEstimate: number;
  activeDaysPerMonthAssumption: number;
  status: string;
  ledger: LedgerCall[];
  actions: { kind: string; status: string; milliseconds: number }[];
  nativeCalls?: { operationId: string; task: string; status: string }[];
}
export function summarizeSession(session: SessionEvidence) {
  let cost = 0n,
    hold = 0n;
  let unknown = 0;
  const tasks: Record<string, { calls: number; nanoyuan: string }> = {};
  for (const call of session.ledger) {
    const amount = call.settledUnits === null ? 0n : BigInt(call.settledUnits);
    cost += amount;
    if (["pending", "dispatched", "reserved"].includes(call.status)) {
      unknown++;
      hold += BigInt(call.reservedUnits);
    }
    const group = tasks[call.task] ?? { calls: 0, nanoyuan: "0" };
    group.calls++;
    group.nanoyuan = String(BigInt(group.nanoyuan) + amount);
    tasks[call.task] = group;
  }
  const cny = Number(cost) / 1e9;
  const pricedCalls = session.ledger.filter((c) => c.status !== "released");
  const sameUsageNoCacheCny = pricedCalls.every(
    (c) => c.usage && c.price.input && c.price.output,
  )
    ? Number(
        pricedCalls.reduce(
          (n, c) =>
            n +
            BigInt(c.usage?.inputTokens ?? 0) * BigInt(c.price.input ?? 0) +
            BigInt(c.usage?.outputTokens ?? 0) * BigInt(c.price.output ?? 0),
          0n,
        ),
      ) / 1e9
    : null;
  const failedActions = session.actions.filter((a) => a.status !== "completed").length;
  const clientFailedAttempts = (session.nativeCalls ?? []).filter((c) =>
    c.status.startsWith("failed"),
  ).length;
  const quotaDeniedAttempts = (session.nativeCalls ?? []).filter((c) =>
    /积分|额度|CREDITS_EXHAUSTED/.test(c.status),
  ).length;
  const effectiveStatus =
    session.status === "completed" && (failedActions > 0 || quotaDeniedAttempts > 0)
      ? "completed_with_gaps"
      : session.status;
  const latencies = session.actions
    .filter((a) => a.kind === "chat" && a.status === "completed")
    .map((a) => a.milliseconds)
    .sort((a, b) => a - b);
  return {
    id: session.id,
    persona: session.persona,
    plan: session.plan,
    status: effectiveStatus,
    failedActions,
    clientFailedAttempts,
    quotaDeniedAttempts,
    completedTurns: session.completedTurns,
    plannedTurns: session.plannedTurns,
    measuredCostCny: cny,
    sameUsageNoCacheCny,
    noCacheIsCounterfactual: true,
    settledNanoyuan: String(cost),
    unknownCalls: unknown,
    heldNanoyuan: String(hold),
    costIsComplete: unknown === 0,
    calls: session.ledger.length,
    inputTokens: session.ledger.reduce((n, c) => n + (c.usage?.inputTokens ?? 0), 0),
    outputTokens: session.ledger.reduce((n, c) => n + (c.usage?.outputTokens ?? 0), 0),
    cacheHitTokens: session.ledger.reduce(
      (n, c) => n + (c.usage?.cacheHitTokens ?? 0),
      0,
    ),
    cacheMissTokens: session.ledger.reduce(
      (n, c) => n + (c.usage?.cacheMissTokens ?? 0),
      0,
    ),
    missingCacheBreakdownCalls: session.ledger.filter(
      (c) =>
        c.usage?.cacheHitTokens === undefined || c.usage.cacheMissTokens === undefined,
    ).length,
    tasks,
    auxiliaryCostCny:
      Number(
        session.ledger
          .filter((c) => c.task !== "conversation" && c.task !== "character_generation")
          .reduce((s, c) => s + BigInt(c.settledUnits ?? "0"), 0n),
      ) / 1e9,
    timingScope: "action_to_reply_and_auxiliary_drain_including_2s_quiet_wait",
    latencyMedianMs: latencies.length
      ? latencies[Math.floor(latencies.length / 2)]
      : null,
    latencyP95Ms: latencies.length
      ? latencies[Math.ceil(latencies.length * 0.95) - 1]
      : null,
    // Intentional null: a cut-short session is a censored sample, not cheap successful usage.
    projectedMonthlyCny:
      effectiveStatus === "completed" && unknown === 0
        ? cny * session.activeDaysPerMonthAssumption
        : null,
    activeDaysPerMonthAssumption: session.activeDaysPerMonthAssumption,
    simulatedMinutes: session.activeMinutesEstimate,
    minutesAreMeasured: false,
  };
}
export function pricingSensitivity(
  monthlyModelCny: number,
  price: number,
  freeUsersPerPayer: number,
  freeModelCny: number,
  otherCostsPerPayer: number,
) {
  const net = price * 0.85;
  return {
    price,
    channelRate: 0.15,
    netRevenue: net,
    monthlyModelCny,
    freeSubsidy: freeUsersPerPayer * freeModelCny,
    otherCostsPerPayer,
    contributionBeforeFixedCosts:
      net - monthlyModelCny - freeUsersPerPayer * freeModelCny - otherCostsPerPayer,
  };
}
