#!/usr/bin/env node
// Records explicit visual decisions; does not infer acceptance from a similarity score.
import { readFileSync, writeFileSync, copyFileSync, mkdirSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
const folder = resolve(import.meta.dirname, "../../Assets/NPC/Library/v3");
const path = resolve(folder, "catalog.json");
const catalog = JSON.parse(readFileSync(path));
const [decisionsPath, neighborsPath] = process.argv.slice(2);
if (!decisionsPath || !neighborsPath)
  throw Error("Usage: npc-record-review.mjs decisions.json neighbors.json");
const decisions = JSON.parse(readFileSync(decisionsPath));
const neighbors = JSON.parse(readFileSync(neighborsPath));
for (const d of decisions) {
  const e = catalog.entries.find((e) => e.key === d.key);
  if (!e || e.status === "accepted")
    throw Error(`Missing or already reviewed: ${d.key}`);
  const record = neighbors.records.find((r) => r.key === d.key);
  const sha256 = createHash("sha256")
    .update(readFileSync(resolve(folder, e.image)))
    .digest("hex");
  if (record?.sha256 !== sha256) throw Error(`Stale comparison: ${d.key}`);
  if (
    !d.notes ||
    !d.appearance ||
    !d.ageMin ||
    !d.ageMax ||
    !d.facing ||
    !d.expression
  )
    throw Error(`Incomplete visual review: ${d.key}`);
  const tags = [
    `theme:${e.target.theme}`,
    `facing:${d.facing}`,
    `expression:${d.expression}`,
    "use:avatar",
    ...(d.tags ?? []),
  ];
  if (d.body && d.body !== "unknown") tags.push(`body:${d.body}`);
  e.observed = {
    ageMin: d.ageMin,
    ageMax: d.ageMax,
    gender: e.target.gender,
    theme: e.target.theme,
    facing: d.facing,
    expression: d.expression,
    body: d.body ?? "unknown",
    appearance: d.appearance,
    tags: [...new Set(tags)],
  };
  e.status = d.reject ? "rejected" : "accepted";
  e.review = {
    status: e.status,
    sha256,
    reviewer: "Codex visual review",
    reviewedAt: new Date().toISOString(),
    circlePass: !d.reject,
    backgroundPass: !d.reject,
    reviewScope: `${neighbors.records.length}-image circular context plus grayscale top-five mirror-aware shortlist`,
    nearestCandidates: record.nearest.slice(0, 5),
    notes: d.notes,
  };
}
writeFileSync(path, JSON.stringify(catalog, null, 2) + "\n");
const reviews = resolve(folder, "../reviews");
mkdirSync(reviews, { recursive: true });
copyFileSync(
  neighborsPath,
  resolve(
    reviews,
    `round-${String(neighbors.records.length).padStart(3, "0")}-${createHash("sha256").update(readFileSync(neighborsPath)).digest("hex").slice(0, 10)}-neighbors.json`,
  ),
);
console.log(
  JSON.stringify({
    reviewed: decisions.length,
    accepted: catalog.entries.filter((e) => e.status === "accepted").length,
  }),
);
