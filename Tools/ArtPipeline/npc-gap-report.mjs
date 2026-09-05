#!/usr/bin/env node
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
const [folder, output] = process.argv.slice(2);
if (!folder || !output)
  throw Error("Usage: npc-gap-report.mjs round-folder output.json");
const runs = readdirSync(folder)
  .filter((n) => /^seed-\d+\.json$/.test(n))
  .map((n) => JSON.parse(readFileSync(resolve(folder, n))));
if (
  !runs.length ||
  runs.some((r) => !r.complete || r.cases.length !== r.expectedCases) ||
  new Set(runs.map((r) => r.catalogSha256)).size !== 1
)
  throw Error("Need completed rounds from the same catalog snapshot");
const cases = runs.flatMap((r) => r.cases),
  groups = new Map();
for (const c of cases) {
  if (c.eligibleCount >= 3 && c.unseenCount > 0) continue;
  const reason =
    c.eligibleCount === 0
      ? "coverage_gap"
      : c.unseenCount === 0
        ? "user_pool_exhausted"
        : "weak_depth";
  const ageMin = [14, 18, 25, 35, 45, 55, 65, 75]
    .filter((n) => n <= c.request.age)
    .at(-1);
  const key = JSON.stringify([
    ageMin,
    c.request.gender,
    [...c.request.requiredTags].sort(),
    reason,
  ]);
  const g = groups.get(key);
  if (g) {
    g.count++;
    g.minCandidates = Math.min(g.minCandidates, c.eligibleCount);
  } else
    groups.set(key, {
      request: c.request,
      ageMin,
      count: 1,
      reason,
      minCandidates: c.eligibleCount,
    });
}
const stats = {
  cases: cases.length,
  matched: cases.filter((c) => c.status === 200).length,
  coverageGaps: cases.filter((c) => c.reason === "coverage_gap").length,
  exhausted: cases.filter((c) => c.reason === "user_pool_exhausted").length,
  weakDepth: cases.filter((c) => c.eligibleCount > 0 && c.eligibleCount < 3)
    .length,
  distinctSelectedAvatars: new Set(
    cases.map((c) => c.selectedAvatarId).filter(Boolean),
  ).size,
};
const result = {
  version: 1,
  accepted: runs[0].accepted,
  catalogSha256: runs[0].catalogSha256,
  seeds: runs.map((r) => r.seed),
  createdAt: new Date().toISOString(),
  stats,
  gaps: [...groups.values()].sort((a, b) => b.count - a.count),
  boundaries: runs[0].boundaries,
};
mkdirSync(dirname(resolve(output)), { recursive: true });
writeFileSync(output, JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify(stats));
