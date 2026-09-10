import type { DatabaseResource } from "../../db/client.js";

type SummaryRow = Readonly<{
  cache_hit_tokens: string;
  cancelled: string;
  cost_cny: string;
  failed: string;
  input_tokens: string;
  output_tokens: string;
  provider_cost_usd: string;
  requests: string;
  succeeded: string;
  unknown_cost_requests: string;
  users: string;
  latency_p50_ms: number | null;
  latency_p95_ms: number | null;
}>;

type GroupRow = Readonly<{
  cache_hit_tokens: string;
  cost_cny: string;
  failed: string;
  input_tokens: string;
  key: string;
  output_tokens: string;
  provider_cost_usd: string;
  requests: string;
  succeeded: string;
  latency_p95_ms: number | null;
}>;

type UserRow = GroupRow & Readonly<{ plan: string | null }>;
type RecentRow = Readonly<{
  cost_cny: string | null;
  error_code: string | null;
  latency_ms: number | null;
  model: string;
  provider: string;
  provider_cost_usd: string | null;
  requested_at: string;
  status: string;
  task: string;
  user_id: string;
}>;

function group(row: GroupRow) {
  return {
    cacheHitTokens: Number(row.cache_hit_tokens),
    costCny: row.cost_cny,
    failed: Number(row.failed),
    inputTokens: Number(row.input_tokens),
    key: row.key,
    latencyP95Ms: row.latency_p95_ms,
    outputTokens: Number(row.output_tokens),
    providerCostUsd: row.provider_cost_usd,
    requests: Number(row.requests),
    succeeded: Number(row.succeeded),
  };
}

export class AiAnalyticsRepository {
  constructor(private readonly database: DatabaseResource) {}

  async report(days: number, userId: string | null) {
    const [summary] = await this.database.sql<SummaryRow[]>`
      select
        count(*)::text as requests,
        count(distinct ar.user_id)::text as users,
        count(*) filter(where ar.status='succeeded')::text as succeeded,
        count(*) filter(where ar.status='failed')::text as failed,
        count(*) filter(where ar.status='cancelled')::text as cancelled,
        coalesce(sum(ar.input_tokens),0)::text as input_tokens,
        coalesce(sum(ar.output_tokens),0)::text as output_tokens,
        coalesce(sum(ar.cache_hit_tokens),0)::text as cache_hit_tokens,
        coalesce(round(sum(ar.provider_cost_usd),9),0)::text as provider_cost_usd,
        coalesce(round(sum(co.settled_units)/1000000000,6),0)::text as cost_cny,
        count(*) filter(where ar.status='succeeded' and co.settled_units is null)::text as unknown_cost_requests,
        percentile_cont(0.5) within group(order by ar.latency_ms) filter(where ar.latency_ms is not null)::real as latency_p50_ms,
        percentile_cont(0.95) within group(order by ar.latency_ms) filter(where ar.latency_ms is not null)::real as latency_p95_ms
      from app.ai_requests ar
      left join app.credit_operations co
        on co.user_id=ar.user_id and co.operation_id=ar.operation_id
      where ar.requested_at >= now()-make_interval(days => ${days})
        and (${userId}::uuid is null or ar.user_id=${userId}::uuid)
    `;
    const groupsFor = async (expression: "day" | "model" | "task") => {
      const key =
        expression === "day"
          ? this.database.sql`to_char(ar.requested_at at time zone 'utc','YYYY-MM-DD')`
          : expression === "model"
            ? this.database.sql`ar.provider::text || '/' || ar.model`
            : this.database.sql`ar.task`;
      const rows = await this.database.sql<GroupRow[]>`
        select
          ${key} as key,
          count(*)::text as requests,
          count(*) filter(where ar.status='succeeded')::text as succeeded,
          count(*) filter(where ar.status='failed')::text as failed,
          coalesce(sum(ar.input_tokens),0)::text as input_tokens,
          coalesce(sum(ar.output_tokens),0)::text as output_tokens,
          coalesce(sum(ar.cache_hit_tokens),0)::text as cache_hit_tokens,
          coalesce(round(sum(ar.provider_cost_usd),9),0)::text as provider_cost_usd,
          coalesce(round(sum(co.settled_units)/1000000000,6),0)::text as cost_cny,
          percentile_cont(0.95) within group(order by ar.latency_ms) filter(where ar.latency_ms is not null)::real as latency_p95_ms
        from app.ai_requests ar
        left join app.credit_operations co
          on co.user_id=ar.user_id and co.operation_id=ar.operation_id
        where ar.requested_at >= now()-make_interval(days => ${days})
          and (${userId}::uuid is null or ar.user_id=${userId}::uuid)
        group by ${key}
        order by ${key}
      `;
      return rows.map(group);
    };
    const [byDay, byModel, byTask, users, recent] = await Promise.all([
      groupsFor("day"),
      groupsFor("model"),
      groupsFor("task"),
      this.database.sql<UserRow[]>`
        select
          ar.user_id::text as key,
          (array_agg(co.plan order by ar.requested_at desc) filter(where co.plan is not null))[1] as plan,
          count(*)::text as requests,
          count(*) filter(where ar.status='succeeded')::text as succeeded,
          count(*) filter(where ar.status='failed')::text as failed,
          coalesce(sum(ar.input_tokens),0)::text as input_tokens,
          coalesce(sum(ar.output_tokens),0)::text as output_tokens,
          coalesce(sum(ar.cache_hit_tokens),0)::text as cache_hit_tokens,
          coalesce(round(sum(ar.provider_cost_usd),9),0)::text as provider_cost_usd,
          coalesce(round(sum(co.settled_units)/1000000000,6),0)::text as cost_cny,
          percentile_cont(0.95) within group(order by ar.latency_ms) filter(where ar.latency_ms is not null)::real as latency_p95_ms
        from app.ai_requests ar
        left join app.credit_operations co
          on co.user_id=ar.user_id and co.operation_id=ar.operation_id
        where ar.requested_at >= now()-make_interval(days => ${days})
          and (${userId}::uuid is null or ar.user_id=${userId}::uuid)
        group by ar.user_id
        order by sum(co.settled_units) desc nulls last, count(*) desc
        limit 200
      `,
      this.database.sql<RecentRow[]>`
        select
          ar.user_id::text,
          ar.task,
          ar.provider::text,
          ar.model,
          ar.status::text,
          ar.error_code,
          ar.latency_ms,
          ar.provider_cost_usd::text,
          (co.settled_units/1000000000)::text as cost_cny,
          ar.requested_at::text
        from app.ai_requests ar
        left join app.credit_operations co
          on co.user_id=ar.user_id and co.operation_id=ar.operation_id
        where ar.requested_at >= now()-make_interval(days => ${days})
          and (${userId}::uuid is null or ar.user_id=${userId}::uuid)
        order by ar.requested_at desc
        limit 100
      `,
    ]);
    return {
      byDay,
      byModel,
      byTask,
      generatedAt: new Date().toISOString(),
      rangeDays: days,
      recent: recent.map((row) => ({
        costCny: row.cost_cny,
        errorCode: row.error_code,
        latencyMs: row.latency_ms,
        model: row.model,
        provider: row.provider,
        providerCostUsd: row.provider_cost_usd,
        requestedAt: new Date(row.requested_at).toISOString(),
        status: row.status,
        task: row.task,
        userId: row.user_id,
      })),
      summary: {
        cacheHitTokens: Number(summary?.cache_hit_tokens ?? 0),
        cancelled: Number(summary?.cancelled ?? 0),
        costCny: summary?.cost_cny ?? "0",
        failed: Number(summary?.failed ?? 0),
        inputTokens: Number(summary?.input_tokens ?? 0),
        latencyP50Ms: summary?.latency_p50_ms ?? null,
        latencyP95Ms: summary?.latency_p95_ms ?? null,
        outputTokens: Number(summary?.output_tokens ?? 0),
        providerCostUsd: summary?.provider_cost_usd ?? "0",
        requests: Number(summary?.requests ?? 0),
        succeeded: Number(summary?.succeeded ?? 0),
        unknownCostRequests: Number(summary?.unknown_cost_requests ?? 0),
        users: Number(summary?.users ?? 0),
      },
      users: users.map((row) => ({ ...group(row), plan: row.plan })),
    };
  }
}
