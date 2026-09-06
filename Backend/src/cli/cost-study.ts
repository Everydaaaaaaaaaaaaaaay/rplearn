import { readFile, mkdir, writeFile } from "node:fs/promises";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { loadCreditPriceBook } from "../modules/access/credit-pricing.js";
import { planEconomics, summarizeStratum } from "../evaluations/cost-study.js";
import type { SessionEvidence } from "../evaluations/cost-report.js";

interface RunReport {
  runId: string;
  scenarioHash: string;
  rawSessions: SessionEvidence[];
  unattributed?: unknown;
}
async function main() {
  const [outputArg, ...inputArgs] = process.argv.slice(2);
  if (!outputArg || !inputArgs.length)
    throw new Error("Usage: cost-study OUTPUT_DIRECTORY RUN_DIRECTORY...");
  const output = resolve(outputArg);
  const book = loadCreditPriceBook();
  const assumptions = JSON.parse(
    await readFile(
      new URL("../../config/cost-study-assumptions.json", import.meta.url),
      "utf8",
    ),
  ) as {
    scopeOverrides: Record<string, string>;
    candidatePricesCny: number[];
    candidateMonthlyModelBudgetsCny: number[];
    freeUsersPerPayerScenarios: number[];
    freeModelMonthlyCnyScenarios: number[];
    otherVariableCnyPerPayer: number;
    grossRefundTaxBufferRate: number;
    targetContributionRateOfNet: number;
    dailyBalanceCandidatesCny: number[];
    monthlyActiveDaysScenarios: number[];
  };
  const groups = new Map<string, SessionEvidence[]>();
  const provenance: unknown[] = [];
  const seen = new Set<string>();
  for (const directory of inputArgs) {
    const raw = await readFile(resolve(directory, "report.json"), "utf8");
    const report = JSON.parse(raw) as RunReport;
    if (seen.has(report.runId))
      throw new Error("Duplicate run would double-count the evidence");
    seen.add(report.runId);
    const env = JSON.parse(
      await readFile(resolve(directory, "environment.json"), "utf8"),
    ) as Record<string, unknown>;
    const routeFingerprint = createHash("sha256")
      .update(JSON.stringify(env.routes))
      .digest("hex");
    provenance.push({
      directory: resolve(directory),
      runId: report.runId,
      scenarioHash: report.scenarioHash,
      reportSha256: createHash("sha256").update(raw).digest("hex"),
      sourceRevision: env.sourceRevision,
      sourceDirty: env.sourceDirty,
      nativeExecutables: env.nativeExecutables,
      executions: env.executions,
      policy: env.policy,
      unattributed: report.unattributed,
    });
    for (const session of report.rawSessions) {
      // Do not silently pool different programs, routes or scenarios into one estimate.
      const key = [
        report.runId,
        report.scenarioHash,
        routeFingerprint,
        session.scenarioId ?? session.id.replace(/-r\d+$/, ""),
      ].join("/");
      groups.set(key, [...(groups.get(key) ?? []), session]);
    }
  }
  const strata = [...groups].map(([key, sessions]) => {
    const scenario = sessions[0]?.scenarioId ?? sessions[0]?.id ?? key;
    const stratum = summarizeStratum(sessions, book);
    const scope = assumptions.scopeOverrides[scenario] ?? "app_workflow";
    return {
      key,
      scenario,
      scope,
      label: sessions[0]?.persona,
      ...stratum,
      fixedWorkloadDailyCoverage: assumptions.dailyBalanceCandidatesCny.map(
        (balanceCny) => ({
          balanceCny,
          completeKnownSamples: stratum.completedWithoutGaps,
          actualHeadroomFits: stratum.rows.filter(
            (s) =>
              s.headroomCoversFullPlannedJourney &&
              s.minimumCnyForObservedRequests !== null &&
              s.minimumCnyForObservedRequests <= balanceCny,
          ).length,
          peakHeadroomFits: stratum.rows.filter(
            (s) =>
              s.headroomCoversFullPlannedJourney &&
              s.minimumCnyForPeakObservedRequests !== null &&
              s.minimumCnyForPeakObservedRequests <= balanceCny,
          ).length,
          windowAwareHeadroomFits: stratum.rows.filter(
            (s) =>
              s.headroomCoversFullPlannedJourney &&
              s.windowAwareReservationHeadroomCny !== null &&
              s.windowAwareReservationHeadroomCny <= balanceCny,
          ).length,
          interpretation:
            "Counterfactual unchanged workload, not a live quota intervention or population success rate.",
        }),
      ),
      hypotheticalMonthlyWorkloads:
        scope === "app_workflow"
          ? assumptions.monthlyActiveDaysScenarios.map((days) => ({
              days,
              sessionsPerDay: 1,
              peakNoCacheCostRange: stratum.completeOnlyPeakNoCacheCny
                ? {
                    min: (stratum.completeOnlyPeakNoCacheCny.min ?? 0) * days,
                    max: (stratum.completeOnlyPeakNoCacheCny.max ?? 0) * days,
                  }
                : null,
              interpretation:
                "Repeated fixed session assumption; real cross-day growth and retention were not measured.",
            }))
          : [],
    };
  });
  const candidates = assumptions.candidatePricesCny.flatMap((price) =>
    assumptions.candidateMonthlyModelBudgetsCny.flatMap((monthlyModelBudget) =>
      assumptions.freeUsersPerPayerScenarios.flatMap((freeUsersPerPayer) =>
        assumptions.freeModelMonthlyCnyScenarios.map((freeCostPerMonth) =>
          planEconomics({
            price,
            monthlyModelBudget,
            freeUsersPerPayer,
            freeCostPerMonth,
            otherVariableCosts: assumptions.otherVariableCnyPerPayer,
            grossRefundTaxBufferRate: assumptions.grossRefundTaxBufferRate,
            targetContributionRate: assumptions.targetContributionRateOfNet,
          }),
        ),
      ),
    ),
  );
  const report = {
    createdAt: new Date().toISOString(),
    provenance,
    priceBook: book,
    strata,
    candidates,
    assumptions: {
      ...assumptions,
      candidateEconomicsUseFullBudget: true,
      freeCostsAreScenarios: true,
      futureRetentionAndWillingnessToPayAreUnmeasured: true,
    },
  };
  const span = (r: ReturnType<typeof summarizeStratum>["completeOnlyActualCny"]) =>
    r
      ? `${r.min?.toFixed(4) ?? "?"} / ${r.median?.toFixed(4) ?? "?"} / ${r.max?.toFixed(4) ?? "?"}`
      : "无完整样本";
  const lines = [
    "# 分层成本与额度评估",
    "",
    "金额：人民币。区间为完整无降级样本的最小 / 中位 / 最大；不代表人群分布。所有失败/中断支出另行保留。",
    "",
    "| 场景 | 完整/样本 | 完成/计划轮次 | 全部账本费用 | 完整会话费用区间 | 同用量高峰区间 | 同用量高峰无缓存区间 |",
    "|---|---:|---:|---:|---|---|---|",
    ...strata.map(
      (s) =>
        `| ${s.label ?? s.scenario}（${s.scope}） | ${String(s.completedWithoutGaps)}/${String(s.samples)} | ${String(s.completedTurns)}/${String(s.plannedTurns)} | ¥${s.actualSpendAllSamplesCny.toFixed(6)} | ${span(s.completeOnlyActualCny)} | ${span(s.completeOnlyPeakCny)} | ${span(s.completeOnlyPeakNoCacheCny)} |`,
    ),
    "",
    "高峰和无缓存数值为固定已测 token 的反事实重计价；最小所需余额还受预留影响，见 study.json 中 minimumCnyForObservedRequests。中断时该数值仅覆盖已接受的调用。",
    "",
    `候选价格测算全部按模型预算用满，渠道 15%，其他可变费用 ¥${String(assumptions.otherVariableCnyPerPayer)}/付费用户/月、退款税费缓冲为标价 ${String(assumptions.grossRefundTaxBufferRate * 100)}%、目标贡献为渠道后收入 ${String(assumptions.targetContributionRateOfNet * 100)}%。这些均为规划假设，不是实测运营利润。账本费用由供应商用量与冻结费率计算，尚非供应商账单核销金额。`,
  ];
  await mkdir(output, { recursive: true });
  await writeFile(resolve(output, "study.json"), JSON.stringify(report, null, 2));
  await writeFile(resolve(output, "study.md"), lines.join("\n") + "\n");
  process.stdout.write(`${resolve(output, "study.md")}\n`);
}
void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : "Study failed"}\n`);
  process.exitCode = 1;
});
