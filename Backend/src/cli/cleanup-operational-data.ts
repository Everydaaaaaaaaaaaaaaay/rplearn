import "dotenv/config";
import { ConfigurationError, loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import { createMediaService } from "../modules/media/service.js";

async function main(): Promise<void> {
  let config: ReturnType<typeof loadConfig>;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigurationError) {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
      return;
    }
    throw error;
  }

  const database = createDatabase(config);
  try {
    const expiredMediaUploads = config.mediaStorageEnabled
      ? await createMediaService(
          config,
          database,
          createMediaObjectStore(config),
        ).expirePendingUploads()
      : 0;
    const auditRows = await database.sql<{ id: string }[]>`
      delete from app.audit_events
      where created_at <
        now() - (${config.auditRetentionDays} * interval '1 day')
      returning id::text
    `;
    const requestRows = await database.sql<{ id: string }[]>`
      delete from app.ai_requests
      where requested_at <
        now() - (${config.aiUsageRetentionDays} * interval '1 day')
      returning id::text
    `;
    const usageRows = await database.sql<{ usage_date: string }[]>`
      delete from app.ai_daily_usage
      where usage_date <
        (now() at time zone 'utc')::date - ${config.aiUsageRetentionDays}
      returning usage_date::text
    `;
    const jobRows = await database.sql<{ id: string }[]>`
      delete from app.jobs
      where status in ('succeeded', 'dead', 'cancelled')
        and completed_at <
          now() - (${config.jobRetentionDays} * interval '1 day')
      returning id::text
    `;
    const deletionReceiptRows = await database.sql<{ id: string }[]>`
      delete from app.account_deletion_requests
      where status in ('completed', 'cancelled')
        and coalesce(completed_at, cancelled_at) <
          now() -
          (${config.accountDeletionReceiptRetentionDays} * interval '1 day')
      returning id::text
    `;
    const mediaRows = await database.sql<{ id: string }[]>`
      delete from app.media_assets
      where status = 'deleted'
        and purged_at <
          now() - (${config.mediaRecordRetentionDays} * interval '1 day')
      returning id::text
    `;
    process.stdout.write(
      `${JSON.stringify({
        deleted: {
          aiDailyUsage: usageRows.length,
          aiRequests: requestRows.length,
          auditEvents: auditRows.length,
          deletionReceipts: deletionReceiptRows.length,
          jobs: jobRows.length,
          mediaRecords: mediaRows.length,
        },
        expiredMediaUploads,
      })}\n`,
    );
  } finally {
    await database.close();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(`${error instanceof Error ? error.name : "UnknownError"}\n`);
  process.exitCode = 1;
});
