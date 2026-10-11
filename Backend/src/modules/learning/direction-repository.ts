import type { TransactionSql } from "postgres";
import { AppError } from "../../shared/errors.js";
import { learningDirections, type LearningDirection } from "./direction.js";

/** 由学习账号事务锁保护，与开始挑战、收据使用同一事务边界。 */
export class LearningDirectionSession {
  constructor(
    private readonly sql: TransactionSql,
    private readonly userId: string,
  ) {}

  async read() {
    const [row] = await this.sql<
      { direction: LearningDirection; revision: number }[]
    >`select direction,revision from app.learning_preferences where user_id=${this.userId}`;
    return {
      selectedDirection: row?.direction ?? ("general" as const),
      revision: row?.revision ?? 0,
      directions: learningDirections,
    };
  }

  async select(direction: LearningDirection, expectedRevision: number) {
    const current = await this.read();
    if (current.revision !== expectedRevision)
      throw new AppError({
        code: "LEARNING_DIRECTION_CONFLICT",
        message: "备考方向已在其他设备更改，请刷新后重试。",
        statusCode: 409,
      });
    if (current.selectedDirection === direction) return current;
    await this.sql`insert into app.learning_preferences(user_id,direction,revision)
      values(${this.userId},${direction},1)
      on conflict(user_id) do update set direction=excluded.direction,
        revision=app.learning_preferences.revision+1,updated_at=now()`;
    return this.read();
  }
}
