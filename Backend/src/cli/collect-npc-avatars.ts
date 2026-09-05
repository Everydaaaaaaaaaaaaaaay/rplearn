import { readFile, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { parseArgs } from "node:util";
import { atomicJSON, collectCandidates } from "../modules/npc/collection/collector.js";
import { collectionReport, reviewHTML } from "../modules/npc/collection/report.js";
import { discoveryPlanSchema } from "../modules/npc/collection/types.js";

async function main() {
  const { values } = parseArgs({
    args: process.argv.slice(2).filter((arg) => arg !== "--"),
    options: {
      plan: { type: "string", default: "npc-avatar-discovery.json" },
      out: { type: "string", default: ".avatar-workbench" },
      pages: { type: "string", default: "1" },
      downloads: { type: "string", default: "120" },
      topics: { type: "string" },
    },
    strict: true,
  });
  const fullPlan = discoveryPlanSchema.parse(
    JSON.parse(await readFile(values.plan, "utf8")) as unknown,
  );
  const plan = { ...fullPlan, topics: [...fullPlan.topics] };
  if (values.topics) {
    const ids = new Set(values.topics.split(","));
    plan.topics = plan.topics.filter((topic) => ids.has(topic.id));
    if (plan.topics.length !== ids.size)
      throw new Error("Unknown or duplicate topic selection");
  }
  const pages = Number(values.pages);
  const downloads = Number(values.downloads);
  if (
    !Number.isInteger(pages) ||
    pages < 0 ||
    pages > 10 ||
    !Number.isInteger(downloads) ||
    downloads < 0 ||
    downloads > 5000
  ) {
    throw new Error("pages must be 0–10; downloads must be 0–5000");
  }
  const directory = resolve(values.out);
  const state = await collectCandidates(
    plan,
    { outputDirectory: directory, maxPagesPerSearch: pages, maxDownloads: downloads },
    undefined,
    (message) => process.stderr.write(message + "\n"),
    async (collected) => {
      await atomicJSON(
        join(directory, "report.json"),
        collectionReport(fullPlan, collected),
      );
      await atomicJSON(join(directory, "plan.json"), fullPlan);
      await writeFile(join(directory, "review.html"), reviewHTML(fullPlan, collected));
    },
  );
  const report = collectionReport(fullPlan, state);
  process.stdout.write(
    JSON.stringify({
      directory,
      discovered: report.discovered,
      downloaded: report.downloaded,
      distinctFiles: report.distinctFiles,
      approved: report.approved,
      searchErrors: report.searchErrors,
      downloadErrors: report.downloadErrors,
    }) + "\n",
  );
  if (report.searchErrors > 0 || report.downloadErrors > 0) process.exitCode = 2;
}
void main().catch((error: unknown) => {
  process.stderr.write(String(error) + "\n");
  process.exitCode = 1;
});
