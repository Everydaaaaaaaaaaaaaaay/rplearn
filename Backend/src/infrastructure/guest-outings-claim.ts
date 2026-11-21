import type { OutingSnapshot } from "../modules/npc/outing-types.js";
import type { TransactionSql } from "postgres";
import { AppError } from "../shared/errors.js";

/** Called while both domain and NPC viewer locks are held by guest claim. */
export async function claimPlaceOutings(
  sql: TransactionSql,
  guestId: string,
  accountId: string,
  keepOuting?: "guest" | "account",
) {
  const [collision] = await sql`
    select 1 from app.npc_outings g join app.npc_outings a
      on a.user_id=${accountId} and a.run_id=g.run_id
    where g.user_id=${guestId} and (g.request_hash<>a.request_hash or g.snapshot<>a.snapshot)
    union all
    select 1 from app.npc_outing_operations g join app.npc_outing_operations a
      on a.user_id=${accountId} and a.run_id=g.run_id and a.operation_id=g.operation_id
    where g.user_id=${guestId} and (g.request_hash<>a.request_hash or g.response<>a.response)

    limit 1`;
  if (collision)
    throw new AppError({
      code: "OUTING_MERGE_CONFLICT",
      message: "同一次外出的两份内容存在冲突，原记录均已保留，请联系支持恢复。",
      statusCode: 409,
    });
  const active = await sql<{ user_id: string; snapshot: OutingSnapshot }[]>`
    select user_id::text,snapshot from app.npc_outings
    where user_id=any(${[guestId, accountId]}::uuid[])
      and status in ('reserved','opening_presented','in_progress')`;
  const guestActive = active.find((row) => row.user_id === guestId);
  const accountActive = active.find((row) => row.user_id === accountId);
  if (
    guestActive &&
    accountActive &&
    guestActive.snapshot.runId !== accountActive.snapshot.runId
  ) {
    if (!keepOuting)
      throw new AppError({
        code: "OUTING_MERGE_CHOICE_REQUIRED",
        statusCode: 409,
        message:
          "游客和账号各有一次进行中的外出。请选择继续哪一次，另一次会结束并保留足迹与阅读记录。",
      });
    const ending = keepOuting === "guest" ? accountActive : guestActive;
    // The claim marker makes this ending and ownership transfer one idempotent transaction.
    const snapshot = {
      ...ending.snapshot,
      status: "abandoned",
      revision: ending.snapshot.revision + 1,
    };
    await sql`update app.npc_outings set snapshot=${JSON.stringify(snapshot)}::jsonb,status='abandoned',updated_at=now()
      where user_id=${ending.user_id} and run_id=${snapshot.runId}`;
  }
  // Keep the guest copy as immutable history; the claim marker prevents a second merge.
  await sql`insert into app.npc_outings(user_id,run_id,request_hash,release_id,city_id,place_id,status,snapshot,created_at,updated_at)
    select ${accountId},run_id,request_hash,release_id,city_id,place_id,status,snapshot,created_at,updated_at
    from app.npc_outings where user_id=${guestId} on conflict(user_id,run_id) do nothing`;
  await sql`insert into app.npc_outing_operations(user_id,run_id,operation_id,request_hash,response,created_at)
    select ${accountId},run_id,operation_id,request_hash,response,created_at
    from app.npc_outing_operations where user_id=${guestId}
    on conflict(user_id,run_id,operation_id) do nothing`;
  await sql`insert into app.npc_outing_city_progress(user_id,city_id,quiet_streak,familiar_streak)
    select ${accountId},city_id,quiet_streak,familiar_streak from app.npc_outing_city_progress where user_id=${guestId}
    on conflict(user_id,city_id) do update set
      quiet_streak=greatest(app.npc_outing_city_progress.quiet_streak,excluded.quiet_streak),
      familiar_streak=greatest(app.npc_outing_city_progress.familiar_streak,excluded.familiar_streak)`;
  // Reconstruct streaks from shown openings in chronological order. Adding counters
  // would count a quiet visit before an encounter as part of the current quiet streak.
  await sql`with shown as (
      select o.city_id,o.run_id,o.snapshot->>'mode' as mode,min(p.created_at) as shown_at
      from app.npc_outings o join app.npc_outing_operations p on p.user_id=o.user_id and p.run_id=o.run_id
      where o.user_id=${accountId} and p.response->>'status'='opening_presented'
      group by o.city_id,o.run_id,o.snapshot->>'mode'
    ), progress as (
      select e.city_id,
        count(*) filter(where e.mode='solitude' and not exists(
          select 1 from shown later where later.city_id=e.city_id and later.mode<>'solitude'
            and (later.shown_at,later.run_id)>(e.shown_at,e.run_id)))::int as quiet_streak,
        count(*) filter(where e.mode='reunion' and not exists(
          select 1 from shown later where later.city_id=e.city_id and later.mode='first_meeting'
            and (later.shown_at,later.run_id)>(e.shown_at,e.run_id)))::int as familiar_streak
      from shown e group by e.city_id
    ) insert into app.npc_outing_city_progress(user_id,city_id,quiet_streak,familiar_streak)
      select ${accountId},city_id,quiet_streak,familiar_streak from progress
      on conflict(user_id,city_id) do update set
        quiet_streak=excluded.quiet_streak,familiar_streak=excluded.familiar_streak`;
}
