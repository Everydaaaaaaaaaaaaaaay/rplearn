import type { DatabaseResource } from "../../db/client.js";
export type LearningSnapshot = Readonly<{ revision: number; payload: string | null }>;
export class LearningRepository {
  constructor(private readonly database: DatabaseResource) {}
  async read(userId: string): Promise<LearningSnapshot> {
    const [row] = await this.database.sql<{ revision: number; payload: string }[]>`
      select revision, payload from app.learning_states where user_id = ${userId}`;
    return row ?? { revision: 0, payload: null };
  }
  async save(
    userId: string,
    expectedRevision: number,
    payload: string,
  ): Promise<LearningSnapshot | null> {
    const [row] = await this.database.sql<{ revision: number; payload: string }[]>`
      insert into app.learning_states (user_id, revision, payload)
      select ${userId}, 1, ${payload} where ${expectedRevision} = 0
      on conflict (user_id) do nothing returning revision, payload`;
    if (row) return row;
    const [updated] = await this.database.sql<{ revision: number; payload: string }[]>`
      update app.learning_states set payload = ${payload}, revision = revision + 1, updated_at = now()
      where user_id = ${userId} and revision = ${expectedRevision}
      returning revision, payload`;
    return updated ?? null;
  }
}
