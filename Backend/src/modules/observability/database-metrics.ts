import type { DatabaseResource } from "../../db/client.js";
import type {
  OperationalMetricsSnapshot,
  OperationalMetricsSource,
} from "./metrics.js";

const JOB_TYPES = new Set([
  "account.purge",
  "auth.email_verification",
  "auth.password_reset",
  "media.delete",
]);
const JOB_STATUSES = new Set(["pending", "running", "succeeded", "dead", "cancelled"]);
const BILLING_ENVIRONMENTS = new Set(["sandbox", "production", "test"]);
const ENTITLEMENT_STATUSES = new Set([
  "active",
  "grace",
  "billing_retry",
  "expired",
  "revoked",
]);
const AI_STATUSES = new Set(["started", "succeeded", "failed", "cancelled"]);
const AI_TASK_PATTERN = /^[a-z][a-z0-9_]{1,63}$/;

function bounded(value: string, allowed: ReadonlySet<string>): string {
  return allowed.has(value) ? value : "other";
}

function taskLabel(value: string): string {
  return AI_TASK_PATTERN.test(value) ? value : "other";
}

function finiteNonnegative(value: string | number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, parsed) : 0;
}

export function createDatabaseMetricsSource(
  database: DatabaseResource,
): OperationalMetricsSource {
  return (): Promise<OperationalMetricsSnapshot> =>
    database.sql.begin(async (sql) => {
      const jobCountRows = await sql<{ count: string; status: string; type: string }[]>`
        select
          case
            when type in (
              'account.purge',
              'auth.email_verification',
              'auth.password_reset',
              'media.delete'
            ) then type
            else 'other'
          end as type,
          status,
          count(*)::text as count
        from app.jobs
        group by 1, status
      `;
      const oldestPendingRows = await sql<{ age_seconds: number; type: string }[]>`
        select
          case
            when type in (
              'account.purge',
              'auth.email_verification',
              'auth.password_reset',
              'media.delete'
            ) then type
            else 'other'
          end as type,
          greatest(
            0,
            extract(epoch from now() - min(available_at))
          )::double precision as age_seconds
        from app.jobs
        where status = 'pending'
        group by 1
      `;
      const subscriptionRows = await sql<
        { count: string; environment: string; status: string }[]
      >`
        select environment, status, count(*)::text as count
        from app.subscriptions
        group by environment, status
      `;
      const reconciliationRows = await sql<{ count: string; environment: string }[]>`
        select environment, count(*)::text as count
        from app.subscriptions
        where provider = 'apple'
          and user_id is not null
          and environment in ('production', 'sandbox')
          and reconcile_after <= now()
        group by environment
      `;
      const billingEventRows = await sql<
        {
          count: string;
          environment: string;
          oldest_age_seconds: number;
        }[]
      >`
        select
          environment,
          count(*)::text as count,
          greatest(
            0,
            extract(epoch from now() - min(received_at))
          )::double precision as oldest_age_seconds
        from app.billing_provider_events
        where processed_at is null
        group by environment
      `;
      const aiRequestRows = await sql<
        {
          count: string;
          input_tokens: string;
          output_tokens: string;
          status: string;
          task: string;
        }[]
      >`
        select
          case
            when task ~ '^[a-z][a-z0-9_]{1,63}$' then task
            else 'other'
          end as task,
          status,
          count(*)::text as count,
          coalesce(sum(input_tokens), 0)::text as input_tokens,
          coalesce(sum(output_tokens), 0)::text as output_tokens
        from app.ai_requests
        where requested_at >= now() - interval '5 minutes'
        group by 1, status
      `;

      return {
        aiRequests: aiRequestRows.map((row) => ({
          count: finiteNonnegative(row.count),
          inputTokens: finiteNonnegative(row.input_tokens),
          outputTokens: finiteNonnegative(row.output_tokens),
          status: bounded(row.status, AI_STATUSES),
          task: taskLabel(row.task),
        })),
        billingEventBacklog: billingEventRows.map((row) => ({
          count: finiteNonnegative(row.count),
          environment: bounded(row.environment, BILLING_ENVIRONMENTS),
          oldestAgeSeconds: finiteNonnegative(row.oldest_age_seconds),
        })),
        billingReconciliationOverdue: reconciliationRows.map((row) => ({
          count: finiteNonnegative(row.count),
          environment: bounded(row.environment, BILLING_ENVIRONMENTS),
        })),
        jobCounts: jobCountRows.map((row) => ({
          count: finiteNonnegative(row.count),
          status: bounded(row.status, JOB_STATUSES),
          type: bounded(row.type, JOB_TYPES),
        })),
        oldestPendingJobs: oldestPendingRows.map((row) => ({
          ageSeconds: finiteNonnegative(row.age_seconds),
          type: bounded(row.type, JOB_TYPES),
        })),
        subscriptionCounts: subscriptionRows.map((row) => ({
          count: finiteNonnegative(row.count),
          environment: bounded(row.environment, BILLING_ENVIRONMENTS),
          status: bounded(row.status, ENTITLEMENT_STATUSES),
        })),
      };
    });
}
