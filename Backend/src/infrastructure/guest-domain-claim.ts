import type { TransactionSql } from "postgres";
import { newEntityId } from "../shared/id.js";
import { appendSyncChange } from "./sync-change-writer.js";

/** Guests cannot spend/transfer coins. Import each earned reward once, not an untrusted client balance. */
export async function claimDomainJourney(
  sql: TransactionSql,
  guestId: string,
  accountId: string,
): Promise<void> {
  await sql`insert into app.user_profiles(user_id) values (${accountId}) on conflict do nothing`;
  await sql`update app.user_profiles a set
    display_name=case when a.has_completed_profile_setup then a.display_name else g.display_name end,
    difficulty=case when a.has_completed_profile_setup then a.difficulty else g.difficulty end,
    learning_goal=case when a.has_completed_profile_setup then a.learning_goal else g.learning_goal end,
    study_stage=case when a.has_completed_profile_setup then a.study_stage else g.study_stage end,
    proficiency_source=case when a.has_completed_profile_setup then a.proficiency_source else g.proficiency_source end,
    placement_score=case when a.has_completed_profile_setup then a.placement_score else g.placement_score end,
    placement_completed_at=case when a.has_completed_profile_setup then a.placement_completed_at else g.placement_completed_at end,
    has_completed_profile_setup=a.has_completed_profile_setup or g.has_completed_profile_setup,
    starter_region_id=case when a.has_completed_onboarding then a.starter_region_id else g.starter_region_id end,
    current_region_id=case when a.has_completed_onboarding then a.current_region_id else g.current_region_id end,
    has_completed_onboarding=a.has_completed_onboarding or g.has_completed_onboarding,
    version=a.version+1,updated_at=now()
    from app.user_profiles g where a.user_id=${accountId} and g.user_id=${guestId}`;
  const rewards = await sql<
    { delta: number; reason: string; reference_id: string; reference_type: string }[]
  >`
    select g.delta,g.reason,g.reference_id,g.reference_type from app.coin_ledger g
    where g.user_id=${guestId} and g.reference_type='story_completion' and g.delta>0
    and not exists(select 1 from app.coin_ledger a where a.user_id=${accountId}
      and a.reference_type=g.reference_type and a.reference_id=g.reference_id)`;
  for (const reward of rewards) {
    const [profile] = await sql<
      { coins: number }[]
    >`update app.user_profiles set coins=coins+${reward.delta},version=version+1,updated_at=now()
      where user_id=${accountId} returning coins`;
    if (!profile) throw new Error("Missing destination profile");
    await sql`insert into app.coin_ledger(id,user_id,delta,balance_after,reason,reference_type,reference_id)
      values (${newEntityId()},${accountId},${reward.delta},${profile.coins},${reward.reason},${reward.reference_type},${reward.reference_id})`;
  }
  await sql`update app.inventory_items g set user_id=${accountId} where g.user_id=${guestId}
    and not exists(select 1 from app.inventory_items a where a.user_id=${accountId}
      and a.source=g.source and a.source_reference_id=g.source_reference_id)`;
  await sql`insert into app.region_unlocks(user_id,region_id,source,unlocked_at)
    select ${accountId},region_id,source,unlocked_at from app.region_unlocks where user_id=${guestId}
    on conflict(user_id,region_id) do nothing`;
  await appendSyncChange(sql, {
    userId: accountId,
    commandId: newEntityId(),
    eventType: "guest.claimed",
    payload: { guestId },
  });
}
