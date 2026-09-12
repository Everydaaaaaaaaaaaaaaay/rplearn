import type { TransactionSql } from "postgres";
import { newEntityId } from "../shared/id.js";

// Call within the caller's transaction. Every coin award locks the same profile first.
export async function awardCoins(
  sql: TransactionSql,
  userId: string,
  amount: number,
  reason: string,
  reference: string,
) {
  const [profile] = await sql<
    { coins: number }[]
  >`select coins from app.user_profiles where user_id=${userId} for update`;
  if (!profile) throw new Error("Profile does not exist");
  const [debt] = await sql<
    { coins: number }[]
  >`select coins from app.coin_adjustment_debts where user_id=${userId}`;
  const offset = Math.min(debt?.coins ?? 0, amount);
  if (offset)
    await sql`update app.coin_adjustment_debts set coins=coins-${offset} where user_id=${userId}`;
  const credited = amount - offset;
  const balance = profile.coins + credited;
  await sql`update app.user_profiles set coins=${balance}, version=version+1, updated_at=now() where user_id=${userId}`;
  // Record even fully debt-offset awards through their caller's persistent grant/completion marker.
  if (credited)
    await sql`insert into app.coin_ledger(id,user_id,delta,balance_after,reason,reference_type,reference_id)
    values(${newEntityId()},${userId},${credited},${balance},${reason},${reason},${reference})`;
  return balance;
}
