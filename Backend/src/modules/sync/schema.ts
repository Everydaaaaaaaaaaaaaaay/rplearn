import {
  bigint,
  index,
  jsonb,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";

export const syncHeads = applicationSchema.table("sync_heads", {
  lastSequence: bigint("last_sequence", { mode: "bigint" }).notNull(),
  updatedAt: timestamp("updated_at", {
    mode: "date",
    withTimezone: true,
  })
    .defaultNow()
    .notNull(),
  userId: uuid("user_id")
    .primaryKey()
    .references(() => users.id, { onDelete: "cascade" }),
});

export const syncChanges = applicationSchema.table(
  "sync_changes",
  {
    commandId: uuid("command_id").notNull(),
    eventId: uuid("event_id").notNull(),
    eventType: text("event_type").notNull(),
    occurredAt: timestamp("occurred_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    payload: jsonb("payload").notNull(),
    sequence: bigint("sequence", { mode: "bigint" }).notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.sequence],
      name: "sync_changes_user_sequence_pk",
    }),
    uniqueIndex("sync_changes_event_unique").on(table.eventId),
    index("sync_changes_user_time_index").on(table.userId, table.occurredAt),
  ],
);
