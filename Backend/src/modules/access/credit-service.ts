import type { TransactionSql } from "postgres";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { loadAccessPolicy } from "../../infrastructure/access-policy.js";
import { AppError } from "../../shared/errors.js";
import type { AiMessage, AiUsage } from "../ai/types.js";
import {
  creditPrice,
  displayCredits,
  exactCreditCost,
  loadCreditPriceBook,
  reservationCost,
  type CreditPrice,
} from "./credit-pricing.js";

const policySchema = z.object({
  version: z.string(),
  guest: z.string().regex(/^\d{1,13}$/),
  free: z.string().regex(/^\d{1,13}$/),
  pro: z.string().regex(/^\d{1,13}$/),
  max: z.string().regex(/^\d{1,13}$/),
});
function reject(code: string, message: string, statusCode = 409): never {
  throw new AppError({ code, message, statusCode });
}
async function lock(sql: TransactionSql, userId: string) {
  await sql`select pg_advisory_xact_lock(hashtextextended(${`usage:${userId}`},0))`;
}
async function context(sql: TransactionSql, userId: string) {
  await lock(sql, userId);
  const [claimed] =
    await sql`select 1 from app.guest_installations where user_id=${userId} and claimed_at is not null`;
  if (claimed) reject("GUEST_ALREADY_CLAIMED", "请登录已认领此旅程的账号。", 403);
  await sql`update app.credit_operations set status=case when status='reserved' then 'released' else 'pending' end,
    reason='reservation_expired',completed_at=now() where user_id=${userId} and status in ('reserved','dispatched') and expires_at<=now()`;
  await sql`update app.credit_operations set result=null where user_id=${userId} and result is not null and completed_at<now()-interval '1 day'`;
  const actor = await loadAccessPolicy(sql, userId);
  const [configuration] = await sql<
    { value: unknown }[]
  >`select value from app.service_metadata where key='model-credits-v1'`;
  const policy = policySchema.parse(configuration?.value);
  if (
    BigInt(policy.pro) < BigInt(policy.free) ||
    BigInt(policy.max) < BigInt(policy.pro)
  )
    throw new Error("Credit upgrade must not reduce daily allowance");
  const [clock] = await sql<
    { at: string; day: string; reset: string }[]
  >`select now()::text as at,
    to_char(now() at time zone 'utc','YYYY-MM-DD') as day,
    ((date_trunc('day',now() at time zone 'utc')+interval '1 day') at time zone 'utc')::text as reset`;
  if (!clock) throw new Error("Missing database clock");
  return {
    actor,
    policy,
    at: new Date(clock.at),
    window: actor.isGuest ? "lifetime" : `day:${clock.day}`,
    reset: actor.isGuest ? null : new Date(clock.reset).toISOString(),
    limit: BigInt(policy[actor.plan]),
  };
}
async function balance(
  sql: TransactionSql,
  userId: string,
  window: string,
  limit: bigint,
) {
  const [row] = await sql<
    { used: string; reserved: string; pending: string; overrun: string }[]
  >`select
    coalesce(sum(settled_units) filter(where status='settled' and window_key=${window}),0)::text as used,
    coalesce(sum(reserved_units) filter(where status in ('reserved','dispatched')),0)::text as reserved,
    coalesce(sum(reserved_units) filter(where status='pending'),0)::text as pending,
    coalesce(sum(greatest(settled_units-reserved_units,0)) filter(where status='settled' and window_key<>${window} and reconciliation is null),0)::text as overrun
    from app.credit_operations where user_id=${userId} and (window_key=${window} or status in ('reserved','dispatched','pending') or (settled_units>reserved_units and reconciliation is null))`;
  const used = BigInt(row?.used ?? 0),
    reserved = BigInt(row?.reserved ?? 0),
    pending = BigInt(row?.pending ?? 0),
    overrun = BigInt(row?.overrun ?? 0);
  const remaining = limit - used - reserved - pending - overrun;
  return {
    limit,
    used,
    reserved,
    pending: pending + overrun,
    remaining: remaining > 0n ? remaining : 0n,
  };
}
export interface CreditSnapshot {
  limit: number;
  used: number;
  reserved: number;
  pending: number;
  remaining: number;
  resetsAt: string | null;
  window: "lifetime" | "day";
  policyVersion: string;
  provisional: true;
  recent: {
    operationId: string;
    task: string;
    status: string;
    credits: number | null;
    heldCredits: number;
    createdAt: string;
  }[];
}
export function createCreditService(database: DatabaseResource) {
  const book = loadCreditPriceBook();
  return {
    snapshot: (userId: string): Promise<CreditSnapshot> =>
      database.sql.begin(async (sql) => {
        const ctx = await context(sql, userId),
          b = await balance(sql, userId, ctx.window, ctx.limit);
        const rows = await sql<
          {
            operation_id: string;
            task: string;
            status: string;
            settled_units: string | null;
            reserved_units: string;
            created_at: string;
          }[]
        >`
        select operation_id::text,task,status,settled_units::text,reserved_units::text,created_at::text from app.credit_operations where user_id=${userId} order by created_at desc limit 20`;
        return {
          limit: displayCredits(b.limit),
          used: displayCredits(b.used),
          reserved: displayCredits(b.reserved),
          pending: displayCredits(b.pending),
          remaining: displayCredits(b.remaining),
          resetsAt: ctx.reset,
          window: ctx.actor.isGuest ? "lifetime" : "day",
          policyVersion: ctx.policy.version,
          provisional: true,
          recent: rows.map((r) => ({
            operationId: r.operation_id,
            task: r.task,
            status: r.status,
            credits:
              r.settled_units === null ? null : displayCredits(BigInt(r.settled_units)),
            heldCredits: displayCredits(BigInt(r.reserved_units)),
            createdAt: new Date(r.created_at).toISOString(),
          })),
        };
      }),
    reserve: (
      userId: string,
      operationId: string,
      hash: string,
      request: {
        task: string;
        provider: string;
        model: string;
        messages: readonly AiMessage[];
        maxOutputTokens: number;
        parentOperationId?: string;
      },
    ): Promise<{ replay: boolean; result: unknown }> =>
      database.sql.begin(async (sql) => {
        const ctx = await context(sql, userId);
        const [old] = await sql<
          { request_hash: string; status: string; result: unknown }[]
        >`select request_hash,status,result from app.credit_operations where user_id=${userId} and operation_id=${operationId}`;
        if (old) {
          if (old.request_hash !== hash)
            reject("OPERATION_CONFLICT", "此请求编号已用于其他内容。");
          if (old.result !== null) return { replay: true, result: old.result };
          reject(
            old.status === "reserved" || old.status === "dispatched"
              ? "OPERATION_IN_PROGRESS"
              : "OPERATION_FINALIZED",
            "此请求已处理或正在核对，请勿重复提交。",
          );
        }
        const [legacy] = await sql<
          { request_hash: string; status: string; result: unknown }[]
        >`select request_hash,status,result from app.usage_operations where user_id=${userId} and operation_id=${operationId}`;
        if (legacy) {
          if (legacy.request_hash !== hash)
            reject("OPERATION_CONFLICT", "此请求编号已用于其他内容。");
          if (legacy.status === "succeeded" && legacy.result !== null)
            return { replay: true, result: legacy.result };
          reject("OPERATION_FINALIZED", "旧版请求已处理，请勿重复提交。");
        }
        if (request.parentOperationId !== undefined) {
          const [parent] =
            await sql`select 1 from app.credit_operations where user_id=${userId} and operation_id=${request.parentOperationId} and task='conversation' and result is not null and completed_at>now()-interval '5 minutes'`;
          const [repair] =
            await sql`select 1 from app.credit_operations where user_id=${userId} and parent_operation_id=${request.parentOperationId}`;
          if (!parent || repair || request.task !== "conversation")
            reject("REPAIR_NOT_ALLOWED", "此回复不能再次修复。");
        }
        const price = creditPrice(book, request.provider, request.model, ctx.at, true);
        const amount = reservationCost(
          price,
          request.messages,
          request.maxOutputTokens,
        );
        const available = await balance(sql, userId, ctx.window, ctx.limit);
        if (amount > available.remaining)
          throw new AppError({
            code: "CREDITS_EXHAUSTED",
            statusCode: 429,
            message: ctx.actor.isGuest
              ? "游客积分不足，登录后可获得每日积分。"
              : "可用积分不足以预留本次请求，请等待恢复或升级订阅。",
            details: {
              remaining: displayCredits(available.remaining),
              required: displayCredits(amount),
              resetsAt: ctx.reset,
              isGuest: ctx.actor.isGuest,
            },
          });
        await sql`insert into app.credit_operations(user_id,operation_id,parent_operation_id,request_hash,task,plan,window_key,policy_version,reserved_units,status,price,expires_at)
        values(${userId},${operationId},${request.parentOperationId ?? null},${hash},${request.task},${ctx.actor.plan},${ctx.window},${ctx.policy.version},${String(amount)},'reserved',${JSON.stringify(price)}::jsonb,now()+interval '5 minutes')`;
        return { replay: false, result: null };
      }),
    dispatch: (userId: string, operationId: string): Promise<void> =>
      database.sql.begin(async (sql) => {
        await lock(sql, userId);
        const [row] = await sql<
          { price: CreditPrice; at: string }[]
        >`select price,now()::text as at from app.credit_operations where user_id=${userId} and operation_id=${operationId} and status='reserved' and expires_at>now() for update`;
        if (!row) reject("OPERATION_FINALIZED", "请求已结束，不能再次调用模型。");
        const price = creditPrice(
          book,
          row.price.provider,
          row.price.model,
          new Date(row.at),
        );
        await sql`update app.credit_operations set status='dispatched',dispatched_at=now(),price=${JSON.stringify(price)}::jsonb where user_id=${userId} and operation_id=${operationId}`;
      }),
    finish: (
      userId: string,
      operationId: string,
      usage: AiUsage | null,
      result: unknown = null,
      providerRequestId: string | null = null,
      model: string | null = null,
      reason: string | null = null,
    ): Promise<void> =>
      database.sql.begin(async (sql) => {
        await lock(sql, userId);
        const [row] = await sql<
          { status: string; price: CreditPrice }[]
        >`select status,price from app.credit_operations where user_id=${userId} and operation_id=${operationId} for update`;
        if (!row || row.status === "settled" || row.status === "released") return;
        if (row.status === "pending" && usage === null && result === null) return;
        const cost =
          model === row.price.model ? exactCreditCost(row.price, usage) : null;
        const status =
          cost !== null
            ? "settled"
            : row.status === "reserved"
              ? "released"
              : "pending";
        await sql`update app.credit_operations set status=${status},settled_units=${cost === null ? null : String(cost)},
        usage=${JSON.stringify(usage)}::jsonb,result=${JSON.stringify(result)}::jsonb,provider_request_id=${providerRequestId},
        reason=${reason ?? (cost === null ? "usage_or_model_unverified" : null)},completed_at=now()
        where user_id=${userId} and operation_id=${operationId}`;
      }),
    // Operator-only service, deliberately absent from public HTTP routes. Evidence is required;
    // pending requests never become free simply because their reservation is old.
    reconcile: (
      userId: string,
      operationId: string,
      units: bigint,
      evidence: string,
    ): Promise<void> =>
      database.sql.begin(async (sql) => {
        if (units < 0n || evidence.trim().length < 10)
          throw new Error(
            "A nonnegative cost and provider billing evidence are required",
          );
        await lock(sql, userId);
        const [previous] = await sql<
          { settled_units: string | null; status: string }[]
        >`select settled_units::text,status from app.credit_operations where user_id=${userId} and operation_id=${operationId} for update`;
        const rows =
          await sql`update app.credit_operations set settled_units=${String(units)},status='settled',completed_at=now(),
        reconciliation=${JSON.stringify({ evidence, previous, at: new Date().toISOString() })}::jsonb where user_id=${userId} and operation_id=${operationId}
        and (status='pending' or (status='settled' and settled_units>reserved_units and reconciliation is null)) returning operation_id`;
        if (rows.length !== 1)
          throw new Error("Operation does not require reconciliation");
      }),
  };
}
