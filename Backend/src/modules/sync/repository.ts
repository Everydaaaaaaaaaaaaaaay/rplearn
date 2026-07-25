import type { DatabaseResource } from "../../db/client.js";
import type { SyncChange } from "./types.js";

type ChangeRow = Readonly<{
  command_id: string;
  event_id: string;
  event_type: string;
  occurred_at: string;
  payload_text: string;
  sequence: string;
}>;

export class SyncRepository {
  constructor(private readonly database: DatabaseResource) {}

  async currentSequence(userId: string): Promise<string> {
    const [head] = await this.database.sql<{ sequence: string }[]>`
      select coalesce(
        (
          select last_sequence
          from app.sync_heads
          where user_id = ${userId}
        ),
        0
      )::text as sequence
    `;
    return head?.sequence ?? "0";
  }

  async changesAfter(
    userId: string,
    sequence: string,
    limit: number,
  ): Promise<Readonly<{ changes: readonly SyncChange[]; hasMore: boolean }>> {
    const rows = await this.database.sql<ChangeRow[]>`
      select
        command_id::text,
        event_id::text,
        event_type,
        occurred_at,
        payload::text as payload_text,
        sequence::text
      from app.sync_changes
      where user_id = ${userId}
        and sequence > ${sequence}::bigint
      order by sequence
      limit ${limit + 1}
    `;
    const hasMore = rows.length > limit;
    return {
      changes: rows.slice(0, limit).map((row) => ({
        commandId: row.command_id,
        eventId: row.event_id,
        eventType: row.event_type,
        occurredAt: new Date(row.occurred_at).toISOString(),
        payload: JSON.parse(row.payload_text) as unknown,
        sequence: row.sequence,
      })),
      hasMore,
    };
  }
}
