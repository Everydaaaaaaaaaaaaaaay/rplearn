import { createCreditService } from "./credit-service.js";
import type { DatabaseResource } from "../../db/client.js";
import type { Sql, TransactionSql } from "postgres";
import {
  loadAccessPolicy,
  type ActorAccessPolicy,
} from "../../infrastructure/access-policy.js";
import { AppError } from "../../shared/errors.js";
import type { AccessSnapshot, UsageKind, UsageReservation } from "./types.js";

/** One lock serializes all pools and plan changes for an actor. PostgreSQL owns time. */
async function context(sql: Sql | TransactionSql, userId: string) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${`usage:${userId}`}, 0))`;
  // Abandoned AI calls release their allowance. Voice leases consume their reserved duration
  // if the client disappears; disconnect/restart cannot grant free repeated voice time.
  await sql`update app.usage_operations set status = case when kind = 'voice' then 'succeeded' else 'failed' end,
    settled_amount = case when kind = 'voice' then amount else 0 end, completed_at = now()
    where user_id = ${userId} and status = 'reserved' and expires_at <= now()`;
  const [claimed] =
    await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
  if (claimed)
    throw new AppError({
      code: "GUEST_ALREADY_CLAIMED",
      message: "请登录已认领此旅程的账号。",
      statusCode: 403,
    });
  await sql`update app.usage_operations set result=null where user_id=${userId} and result is not null and completed_at < now()-interval '1 day'`;
  const policy = await loadAccessPolicy(sql, userId);
  const [clock] = await sql<{ key: string; reset: string | null }[]>`select
    case ${policy.quotaWindow} when 'lifetime' then 'lifetime'
      when 'day' then to_char(now() at time zone 'utc', 'YYYY-MM-DD')
      else to_char(now() at time zone 'utc', 'YYYY-MM') end as key,
    case ${policy.quotaWindow} when 'lifetime' then null
      when 'day' then (date_trunc('day', now() at time zone 'utc') + interval '1 day') at time zone 'utc'
      else (date_trunc('month', now() at time zone 'utc') + interval '1 month') at time zone 'utc' end::text as reset`;
  if (!clock) throw new Error("Missing database clock");
  return {
    policy,
    window: `${policy.quotaWindow}:${clock.key}`,
    resetsAt: clock.reset === null ? null : new Date(clock.reset).toISOString(),
  };
}
function limitFor(policy: ActorAccessPolicy, kind: UsageKind): number {
  switch (kind) {
    case "chat":
      return policy.chatLimit;
    case "advanced":
      return policy.advancedLimit;
    case "voice":
      return policy.voiceSecondsLimit;
    // Automatic memory, correction, translation and quiz work have a separate bounded envelope.
    case "auxiliary":
      return policy.chatLimit * 12 + policy.advancedLimit * 4;
  }
}
async function balance(
  sql: TransactionSql,
  userId: string,
  window: string,
  kind: UsageKind,
  limit: number,
) {
  const [row] = await sql<{ used: number; reserved: number }[]>`select
    coalesce(sum(settled_amount) filter (where status = 'succeeded'), 0)::int as used,
    coalesce(sum(amount) filter (where status = 'reserved'), 0)::int as reserved
    from app.usage_operations where user_id = ${userId} and window_key = ${window} and kind = ${kind}`;
  const used = row?.used ?? 0,
    reserved = row?.reserved ?? 0;
  return { limit, used, reserved, remaining: Math.max(0, limit - used - reserved) };
}
export function createAccessService(database: DatabaseResource) {
  return {
    snapshot: async (userId: string): Promise<AccessSnapshot> => {
      const legacy = await database.sql.begin(async (sql) => {
        const ctx = await context(sql, userId);
        const balances = {} as AccessSnapshot["balances"];
        for (const kind of ["chat", "advanced", "auxiliary", "voice"] as const) {
          balances[kind] = await balance(
            sql,
            userId,
            ctx.window,
            kind,
            limitFor(ctx.policy, kind),
          );
        }
        return { policy: ctx.policy, resetsAt: ctx.resetsAt, balances };
      });
      const credits = await createCreditService(database).snapshot(userId);
      return {
        ...legacy,
        policy: { ...legacy.policy, quotaWindow: credits.window },
        credits,
        resetsAt: credits.resetsAt,
      };
    },
    reserveVoice: async (
      userId: string,
      operationId: string,
    ): Promise<UsageReservation> => {
      const credits = await createCreditService(database).snapshot(userId);
      if (credits.remaining <= 0)
        throw new AppError({
          code: "CREDITS_EXHAUSTED",
          message: "积分不足，请查看用量与权益。",
          statusCode: 429,
        });
      return database.sql.begin(async (sql) => {
        const ctx = await context(sql, userId);
        const [previous] = await sql<
          { kind: string; amount: number; expires_at: string }[]
        >`select kind,amount,expires_at::text from app.usage_operations where user_id=${userId} and operation_id=${operationId}`;
        if (previous) {
          if (previous.kind !== "voice")
            throw new AppError({
              code: "OPERATION_CONFLICT",
              message: "请求编号已使用。",
              statusCode: 409,
            });
          return {
            operationId,
            amount: previous.amount,
            expiresAt: new Date(previous.expires_at).toISOString(),
            replay: true,
            result: null,
          };
        }
        const [active] = await sql<
          { count: number }[]
        >`select count(*)::int as count from app.usage_operations where user_id=${userId} and kind='voice' and status='reserved'`;
        if ((active?.count ?? 0) >= 3)
          throw new AppError({
            code: "VOICE_SESSION_LIMIT",
            message: "请先结束已有语音会话。",
            statusCode: 429,
          });
        const [lease] = await sql<
          { expires_at: string }[]
        >`insert into app.usage_operations(user_id,operation_id,request_hash,kind,window_key,plan,policy_version,amount,status,expires_at)
          values(${userId},${operationId},'voice-credits-v1','voice',${ctx.window},${ctx.policy.plan},${ctx.policy.policyVersion},60,'reserved',now()+interval '60 seconds') returning expires_at::text`;
        if (!lease) throw new Error("Missing voice lease");
        return {
          operationId,
          amount: 60,
          expiresAt: new Date(lease.expires_at).toISOString(),
          replay: false,
          result: null,
        };
      });
    },
    reserve: (
      userId: string,
      operationId: string,
      hash: string,
      kind: UsageKind,
      requested = 1,
      parentOperationId?: string,
      reservationSeconds = 300,
    ): Promise<UsageReservation> =>
      database.sql.begin(async (sql) => {
        const ctx = await context(sql, userId);
        const [previous] = await sql<
          {
            request_hash: string;
            kind: string;
            status: string;
            result: unknown;
            amount: number;
            expires_at: string;
          }[]
        >`
        select request_hash, kind, status, result, amount, expires_at from app.usage_operations
        where user_id = ${userId} and operation_id = ${operationId}`;
        if (previous) {
          if (previous.request_hash !== hash || previous.kind !== kind)
            throw new AppError({
              code: "OPERATION_CONFLICT",
              message: "This operation ID was used for a different request.",
              statusCode: 409,
            });
          if (previous.status === "succeeded")
            return {
              operationId,
              replay: true,
              result:
                typeof previous.result === "string"
                  ? (JSON.parse(previous.result) as unknown)
                  : previous.result,
              amount: previous.amount,
              expiresAt: new Date(previous.expires_at).toISOString(),
            };
          if (previous.status === "reserved") {
            if (kind === "voice")
              return {
                operationId,
                replay: true,
                result: null,
                amount: previous.amount,
                expiresAt: new Date(previous.expires_at).toISOString(),
              };
            throw new AppError({
              code: "OPERATION_IN_PROGRESS",
              message: "The original request is still running. Please wait.",
              statusCode: 409,
            });
          }
        }
        if (parentOperationId !== undefined) {
          const [parent] =
            await sql`select 1 from app.usage_operations where user_id=${userId}
            and operation_id=${parentOperationId} and kind='chat' and status='succeeded' and completed_at>now()-interval '5 minutes'`;
          const [repair] =
            await sql`select 1 from app.usage_operations where user_id=${userId}
            and parent_operation_id=${parentOperationId} and operation_id<>${operationId}`;
          if (!parent || repair || kind !== "auxiliary")
            throw new AppError({
              code: "REPAIR_NOT_ALLOWED",
              message: "This interaction cannot be repaired again.",
              statusCode: 409,
            });
        }
        const available = await balance(
          sql,
          userId,
          ctx.window,
          kind,
          limitFor(ctx.policy, kind),
        );
        const amount =
          kind === "voice" ? Math.min(requested, available.remaining) : requested;
        if (amount < 1 || amount > available.remaining)
          throw new AppError({
            code: "USAGE_QUOTA_EXCEEDED",
            statusCode: 429,
            message: ctx.policy.isGuest
              ? "游客体验额度已用完，登录后可获得每日额度。"
              : "本周期额度已用完，可等待恢复或升级订阅。",
            details: {
              kind,
              isGuest: ctx.policy.isGuest,
              resetsAt: ctx.resetsAt,
              ...available,
            },
          });
        const [row] = await sql<
          { expires_at: string }[]
        >`insert into app.usage_operations
        (user_id,operation_id,parent_operation_id,request_hash,kind,window_key,plan,policy_version,amount,status,expires_at)
        values (${userId},${operationId},${parentOperationId ?? null},${hash},${kind},${ctx.window},${ctx.policy.plan},${ctx.policy.policyVersion},${amount},'reserved',now() + ${kind === "voice" ? amount : Math.max(300, Math.min(900, reservationSeconds))} * interval '1 second')
        on conflict (user_id,operation_id) do update set status='reserved', settled_amount=null, result=null,
          window_key=excluded.window_key, plan=excluded.plan, policy_version=excluded.policy_version,
          amount=excluded.amount, created_at=now(), completed_at=null, expires_at=excluded.expires_at
        returning expires_at`;
        if (!row) throw new Error("Missing reservation");
        return {
          operationId,
          amount,
          expiresAt: new Date(row.expires_at).toISOString(),
          replay: false,
          result: null,
        };
      }),
    settle: (
      userId: string,
      operationId: string,
      succeeded: boolean,
      result: unknown = null,
    ): Promise<void> =>
      database.sql.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtextextended(${`usage:${userId}`}, 0))`;
        await sql`update app.usage_operations set status=${succeeded ? "succeeded" : "failed"},
        settled_amount=case when ${!succeeded} then 0 when kind='voice' then least(amount, greatest(1, ceil(extract(epoch from now()-created_at))::int)) else amount end,
        result=${JSON.stringify(result)}::jsonb, completed_at=now()
        where user_id=${userId} and operation_id=${operationId} and status='reserved'`;
      }),
    stopVoice: async (userId: string, operationId: string): Promise<void> => {
      await database.sql`update app.usage_operations set status='succeeded',
        settled_amount=least(amount,greatest(1,ceil(extract(epoch from now()-created_at))::int)),completed_at=now()
        where user_id=${userId} and operation_id=${operationId} and kind='voice' and status='reserved'`;
    },
    assertVoiceLease: async (userId: string, operationId: string): Promise<void> => {
      const [lease] =
        await database.sql`select 1 from app.usage_operations where user_id=${userId}
        and operation_id=${operationId} and kind='voice' and status='reserved' and expires_at>now()`;
      if (!lease)
        throw new AppError({
          code: "VOICE_LEASE_EXPIRED",
          message: "语音体验时间已结束，请查看剩余额度。",
          statusCode: 429,
        });
    },
  };
}
export type AccessService = ReturnType<typeof createAccessService>;
