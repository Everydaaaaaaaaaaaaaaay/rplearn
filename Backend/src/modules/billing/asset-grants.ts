import type { TransactionSql } from "postgres";
import { awardCoins } from "../../infrastructure/coin-awards.js";
import { appendSyncChange } from "../../infrastructure/sync-change-writer.js";
import { newEntityId } from "../../shared/id.js";
import type { VerifiedStoreTransaction } from "./types.js";

export async function applyAssetGrant(
  sql: TransactionSql,
  userId: string,
  transaction: VerifiedStoreTransaction,
  coins: number,
  tickets: number,
) {
  // Caller serializes by transaction ID. Profile lock serializes grants/refunds across purchases.
  await sql`insert into app.user_profiles(user_id) values(${userId}) on conflict do nothing`;
  await sql`select user_id from app.user_profiles where user_id=${userId} for update`;
  const [prior] = await sql<
    { coins: number; ticket_ids: string[]; revoked: boolean }[]
  >`
    select coins,ticket_ids,revoked from app.billing_asset_grants
    where environment=${transaction.environment}::app.billing_environment and transaction_id=${transaction.transactionId}`;
  const reference = `${transaction.environment}:${transaction.transactionId}`;
  if (transaction.revokedAt) {
    if (prior?.revoked) return;
    if (prior) {
      const [profile] = await sql<
        { coins: number }[]
      >`select coins from app.user_profiles where user_id=${userId}`;
      const reclaimed = Math.min(profile?.coins ?? 0, prior.coins);
      if (reclaimed) {
        await sql`update app.user_profiles set coins=coins-${reclaimed}, version=version+1,updated_at=now() where user_id=${userId}`;
        await sql`insert into app.coin_ledger(id,user_id,delta,balance_after,reason,reference_type,reference_id)
          values(${newEntityId()},${userId},${-reclaimed},${(profile?.coins ?? 0) - reclaimed},'apple_refund','apple_refund',${reference})`;
      }
      const debt = prior.coins - reclaimed;
      if (debt)
        await sql`insert into app.coin_adjustment_debts(user_id,coins) values(${userId},${debt})
        on conflict(user_id) do update set coins=app.coin_adjustment_debts.coins+excluded.coins`;
      // Retain travel history; revoke only unused tickets. Already-used benefits become coin debt.
      await sql<{ id: string }[]>`update app.inventory_items set status='revoked'
        where user_id=${userId} and id=any(${prior.ticket_ids}::uuid[]) and status='available' returning id`;
      const [consumed] = await sql<
        { count: number }[]
      >`select count(*)::int as count from app.inventory_items
        where user_id=${userId} and id=any(${prior.ticket_ids}::uuid[]) and status='consumed'`;
      const usedDebt = (consumed?.count ?? 0) * 500;
      if (usedDebt)
        await sql`insert into app.coin_adjustment_debts(user_id,coins) values(${userId},${usedDebt})
        on conflict(user_id) do update set coins=app.coin_adjustment_debts.coins+excluded.coins`;
    }
    await sql`insert into app.billing_asset_grants(environment,transaction_id,user_id,coins,revoked)
      values(${transaction.environment}::app.billing_environment,${transaction.transactionId},${userId},0,true)
      on conflict(environment,transaction_id) do update set revoked=true`;
  } else {
    if (prior || (!coins && !tickets)) return;
    // Never award a free trial or historical subscription period when replaying entitlements.
    if (
      tickets &&
      (transaction.purchasedAt < new Date("2026-09-12T00:00:00Z") ||
        !transaction.expiresAt ||
        transaction.expiresAt <= new Date() ||
        (transaction.price ?? 0) <= 0)
    )
      return;
    if (coins) await awardCoins(sql, userId, coins, "apple_coins", reference);
    const ids: string[] = [];
    for (let index = 0; index < tickets; index++) {
      const id = newEntityId();
      ids.push(id);
      await sql`insert into app.inventory_items(id,user_id,type,source,source_reference_id)
        values(${id},${userId},'universal','subscription',${`${reference}:${String(index)}`})`;
    }
    await sql`insert into app.billing_asset_grants(environment,transaction_id,user_id,coins,ticket_ids)
      values(${transaction.environment}::app.billing_environment,${transaction.transactionId},${userId},${coins},${ids}::uuid[])`;
  }
  await appendSyncChange(sql, {
    userId,
    commandId: newEntityId(),
    eventType: "billing.assetsUpdated",
    payload: { transactionId: transaction.transactionId },
  });
}
