import "dotenv/config";
import { readFile, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { auditAvatarCoverage } from "../modules/npc/avatar-coverage.js";
import { atomicJSON, loadCollection } from "../modules/npc/collection/collector.js";
import {
  createAvatarPublisher,
  publishCollection,
} from "../modules/npc/collection/publisher.js";
import { prepareReviewedCollection } from "../modules/npc/collection/review.js";
import { discoveryPlanSchema, reviewSchema } from "../modules/npc/collection/types.js";
import { reviewHTML } from "../modules/npc/collection/report.js";

async function main() {
  const { values } = parseArgs({
    args: process.argv.slice(2).filter((arg) => arg !== "--"),
    options: {
      dir: { type: "string", default: ".avatar-workbench" },
      review: { type: "string" },
      "public-base": { type: "string" },
      "review-only": { type: "boolean", default: false },
      publish: { type: "boolean", default: false },
      bucket: { type: "string" },
      prefix: { type: "string", default: "npc-avatars" },
      region: { type: "string", default: "us-east-1" },
      endpoint: { type: "string" },
    },
    strict: true,
  });
  if (!values.review || (!values["review-only"] && !values["public-base"]))
    throw new Error(
      "Required: --review review.json and either --review-only or --public-base https://avatar-cdn.example/npc-avatars/",
    );
  if (values["review-only"] && values.publish)
    throw new Error("--review-only cannot publish");
  const directory = resolve(values.dir);
  const review = reviewSchema.parse(
    JSON.parse(await readFile(values.review, "utf8")) as unknown,
  );
  const state = await loadCollection(directory);
  const prepared = await prepareReviewedCollection(
    directory,
    state,
    review,
    values["public-base"] ?? "https://unpublished.invalid/",
  );
  const reviewedReport = join(directory, "reviewed-report.json");
  await atomicJSON(reviewedReport, {
    version: 1,
    approved: prepared.manifest.avatars.length,
    rejected: review.decisions.filter((decision) => decision.decision === "reject")
      .length,
    pending: Object.keys(state.candidates).length - review.decisions.length,
    coverage: auditAvatarCoverage(prepared.manifest, []),
  });
  const plan = discoveryPlanSchema.parse(
    JSON.parse(await readFile(join(directory, "plan.json"), "utf8")) as unknown,
  );
  await writeFile(
    join(directory, "reviewed.html"),
    reviewHTML(
      plan,
      {
        ...state,
        candidates: Object.fromEntries(
          Object.entries(state.candidates).filter(([id]) =>
            review.decisions.some((decision) => decision.candidateId === id),
          ),
        ),
      },
      review,
    ),
  );
  if (values["review-only"]) {
    process.stdout.write(
      JSON.stringify({ report: reviewedReport, uploaded: false }) + "\n",
    );
    return;
  }
  if (values.publish) {
    if (!values.bucket)
      throw new Error(
        "Publishing requires an explicit --bucket (AWS credentials use the standard SDK chain)",
      );
    await publishCollection(
      prepared,
      createAvatarPublisher({
        bucket: values.bucket,
        prefix: values.prefix,
        region: values.region,
        ...(values.endpoint ? { endpoint: values.endpoint } : {}),
      }),
    );
  }
  const path = join(
    directory,
    values.publish ? "published-manifest.json" : "prepared-manifest.json",
  );
  await atomicJSON(path, prepared.manifest);
  process.stdout.write(
    JSON.stringify({
      manifest: path,
      avatars: prepared.manifest.avatars.length,
      uploaded: values.publish,
    }) + "\n",
  );
}
void main().catch((error: unknown) => {
  process.stderr.write(String(error) + "\n");
  process.exitCode = 1;
});
