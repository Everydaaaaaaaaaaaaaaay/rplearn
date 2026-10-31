import type { TransactionSql } from "postgres";
import { AppError } from "../shared/errors.js";

/** Called while both domain and NPC viewer locks are held by guest claim. */
export async function claimPlaceOutings(
  sql: TransactionSql,
  guestId: string,
  accountId: string,
) {
  const [collision] = await sql`
    select 1 from app.npc_outings g join app.npc_outings a
      on a.user_id=${accountId} and a.run_id=g.run_id
    where g.user_id=${guestId} and (g.request_hash<>a.request_hash or g.snapshot<>a.snapshot)
    union all
    select 1 from app.npc_outing_operations g join app.npc_outing_operations a
      on a.user_id=${accountId} and a.run_id=g.run_id and a.operation_id=g.operation_id
    where g.user_id=${guestId} and (g.request_hash<>a.request_hash or g.response<>a.response)
    union all
    select 1 from app.npc_outings g join app.npc_outings a on a.user_id=${accountId}
    where g.user_id=${guestId} and g.run_id<>a.run_id
      and g.status in ('reserved','opening_presented','in_progress')
      and a.status in ('reserved','opening_presented','in_progress')
    limit 1`;
  if (collision)
    throw new AppError({
      code: "OUTING_MERGE_CONFLICT",
      message:
        "两段旅程的外出进度存在冲突，原记录均已保留。若两边都有进行中的外出，请先结束其中一次再认领；同号内容冲突请联系支持。",
      statusCode: 409,
    });
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
