import type { TransactionSql } from "postgres";

/** 由唯一的年级、星序号约束保证每颗星仅计入一次；与当前自选年级无关。 */
export async function countEarnedStars(
  sql: TransactionSql,
  userId: string,
): Promise<number> {
  const [row] = await sql<{ stars: number }[]>`
    select count(*)::int as stars from app.learning_milestones where user_id=${userId}`;
  return row?.stars ?? 0;
}
