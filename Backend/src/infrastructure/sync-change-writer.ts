import type { TransactionSql } from "postgres";
import { newEntityId } from "../shared/id.js";

export async function appendSyncChange(
  sql: TransactionSql,
  change: Readonly<{
    commandId: string;
    eventType: string;
    payload: unknown;
    userId: string;
  }>,
): Promise<string> {
  const [head] = await sql<{ sequence: string }[]>`
    insert into app.sync_heads (user_id, last_sequence)
    values (${change.userId}, 1)
    on conflict (user_id) do update
    set last_sequence = app.sync_heads.last_sequence + 1,
        updated_at = now()
    returning last_sequence::text as sequence
  `;
  if (head === undefined) {
    throw new Error("Sync sequence allocation did not return a row");
  }

  await sql`
    insert into app.sync_changes (
      user_id,
      sequence,
      event_id,
      command_id,
      event_type,
      payload
    )
    values (
      ${change.userId},
      ${head.sequence}::bigint,
      ${newEntityId()},
      ${change.commandId},
      ${change.eventType},
      ${JSON.stringify(change.payload)}::jsonb
    )
  `;
  return head.sequence;
}
