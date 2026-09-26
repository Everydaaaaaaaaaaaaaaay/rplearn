import { z } from "zod";
import type { TransactionSql } from "postgres";
import type { ContentRecord } from "../content/types.js";
import type { LearningLevel } from "./content.js";
import { AppError } from "../../shared/errors.js";

/** 由组装层连接领域服务；学习仓库不越界读取聊天或档案表。 */
export type PromotionProfile = Readonly<{ difficulty: LearningLevel; version: number }>;
export interface LearningContextReader {
  promotionProfile?: (sql: TransactionSql, userId: string) => Promise<PromotionProfile>;
  promoteProfile?: (
    sql: TransactionSql,
    userId: string,
    requestId: string,
    from: LearningLevel,
    to: LearningLevel,
    expectedVersion: number,
  ) => Promise<PromotionProfile>;
  profile: (sql: TransactionSql, userId: string) => Promise<LearningLevel>;
  character: (
    sql: TransactionSql,
    userId: string,
    characterId: string,
  ) => Promise<string>;
}
const characterSchema = z.object({
  isMainCharacter: z.boolean(),
  card: z.object({ name: z.string(), regionId: z.string() }),
});
const mainRoles = [
  { name: "Oliver Bennett", regionId: "london", key: "oliver" },
  { name: "Ruby Walker", regionId: "melbourne", key: "ruby" },
  { name: "Marcus Rivera", regionId: "newyork", key: "marcus" },
] as const;

export function learningRoleKey(record: ContentRecord | undefined): string {
  const character = characterSchema.safeParse(record?.payload);
  if (
    record?.resourceType !== "character" ||
    record.deletedAt !== null ||
    !character.success
  ) {
    throw new AppError({
      code: "LEARNING_CHARACTER_NOT_FOUND",
      message: "找不到这个角色，请先完成聊天同步。",
      statusCode: 404,
    });
  }
  if (character.data.isMainCharacter) {
    const role = mainRoles.find(
      (r) =>
        r.name === character.data.card.name &&
        r.regionId === character.data.card.regionId,
    );
    if (role) return role.key;
  }
  // 非预设角色保持独立身份；没有审核内容时保留满条，不能借用主角色题库。
  return `character.${record.resourceId.toLowerCase()}`;
}
