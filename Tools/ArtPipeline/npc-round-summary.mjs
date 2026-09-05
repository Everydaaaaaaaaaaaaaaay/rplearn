#!/usr/bin/env node
import { readdirSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
const folder = resolve(import.meta.dirname, "../../Assets/NPC/Library/reports");
const fixedSeeds = [90601, 90602, 90603];
function summarize(reports) {
  const cases = reports.flatMap((r) => r.cases);
  return {
    cases: cases.length,
    matched: cases.filter((c) => c.reason === "matched").length,
    coverageGaps: cases.filter((c) => c.reason === "coverage_gap").length,
    exhausted: cases.filter((c) => c.reason === "user_pool_exhausted").length,
    weakDepth: cases.filter((c) => c.eligibleCount > 0 && c.eligibleCount < 3)
      .length,
  };
}
const rounds = [];
for (const name of readdirSync(folder)
  .filter((n) => /^round-\d+$/.test(n))
  .sort((a, b) => Number(a.slice(6)) - Number(b.slice(6)))) {
  const dir = resolve(folder, name),
    reports = readdirSync(dir)
      .filter((n) => /^seed-\d+\.json$/.test(n))
      .map((n) => JSON.parse(readFileSync(resolve(dir, n))));
  if (!reports.length) continue;
  if (
    reports.some(
      (r) => r.complete !== true || r.cases.length !== r.expectedCases,
    ) ||
    new Set(reports.map((r) => r.catalogSha256)).size !== 1
  )
    throw Error("Incomplete or mixed catalog reports: " + name);
  const baseline = reports.filter((r) => fixedSeeds.includes(r.seed)),
    heldout = reports.filter((r) => !fixedSeeds.includes(r.seed));
  if (baseline.length !== fixedSeeds.length)
    throw Error("Missing baseline seeds " + name);
  rounds.push({
    name,
    accepted: reports[0].accepted,
    catalogSha256: reports[0].catalogSha256,
    seeds: reports.map((r) => r.seed),
    all: summarize(reports),
    baseline: summarize(baseline),
    heldout: summarize(heldout),
  });
}
const report = {
  createdAt: new Date().toISOString(),
  fixedSeeds,
  rounds,
  limitations: [
    "Narrative fixtures are synthetic; no live LLM/native UI/production CDN.",
    "Compare baseline rows with identical request seeds. Production random choices may vary user exhaustion.",
    "Weak depth means eligible pool of one or two, before per-user exclusions; it overlaps successful requests.",
  ],
};
const output = process.argv[2] ?? resolve(folder, "summary.json");
writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
console.log(JSON.stringify(report));
