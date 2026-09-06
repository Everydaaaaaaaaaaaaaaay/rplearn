import "dotenv/config";
import { fileURLToPath } from "node:url";
import { readFile } from "node:fs/promises";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import {
  buildCostReport,
  priceBookSchema,
  type CostObservation,
} from "../modules/access/cost-report.js";
async function main(): Promise<void> {
  const database = createDatabase(loadConfig());
  const since =
    process.env.USAGE_REPORT_SINCE ??
    new Date(Date.now() - 7 * 86400_000).toISOString();
  if (!Number.isFinite(Date.parse(since)))
    throw new Error("USAGE_REPORT_SINCE must be an ISO date");
  const book = priceBookSchema.parse(
    JSON.parse(
      await readFile(
        process.env.AI_PRICE_BOOK ??
          fileURLToPath(new URL("../../config/ai-prices.json", import.meta.url)),
        "utf8",
      ),
    ),
  );
  try {
    const rows = await database.sql<
      CostObservation[]
    >`select a.user_id::text as "userId",a.task,
      coalesce(o.plan,'unknown') as plan,a.operation_id::text as "operationId",a.status,
      a.model,a.provider,a.config_version as "configVersion",a.requested_at::text as "requestedAt",a.input_tokens as "inputTokens",
      a.output_tokens as "outputTokens",a.cache_hit_tokens as "cacheHitTokens",a.cache_miss_tokens as "cacheMissTokens",
      a.provider_attempts as "providerAttempts",a.latency_ms as "latencyMs"
      from app.ai_requests a left join app.usage_operations o on o.user_id=a.user_id and o.operation_id=a.operation_id
      where a.requested_at>=${since}::timestamptz order by a.requested_at limit 100001`;
    if (rows.length > 100000)
      throw new Error("Report too large; narrow USAGE_REPORT_SINCE");
    const normalized = rows.map((row) => ({
      ...row,
      requestedAt: new Date(row.requestedAt).toISOString(),
    }));
    const supply =
      await database.sql`select region_id,activity_id,language,selections,reuses,gaps,candidate_count,updated_at from app.npc_scene_supply order by gaps desc`;
    process.stdout.write(
      JSON.stringify(
        { since, ...buildCostReport(normalized, book), npcSupply: supply },
        null,
        2,
      ) + "\n",
    );
  } finally {
    await database.close();
  }
}
void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.message : "Report failed"}\n`);
  process.exitCode = 1;
});
