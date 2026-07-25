import { index, jsonb, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../auth/schema.js";

export const auditEvents = applicationSchema.table(
  "audit_events",
  {
    action: text("action").notNull(),
    actorKind: text("actor_kind").notNull(),
    actorUserId: uuid("actor_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    id: uuid("id").primaryKey(),
    ipHash: text("ip_hash"),
    metadata: jsonb("metadata").default({}).notNull(),
    outcome: text("outcome").notNull(),
    requestId: text("request_id").notNull(),
    targetId: text("target_id"),
    targetType: text("target_type").notNull(),
  },
  (table) => [
    index("audit_events_created_index").on(table.createdAt),
    index("audit_events_actor_time_index").on(table.actorUserId, table.createdAt),
    index("audit_events_action_time_index").on(table.action, table.createdAt),
  ],
);
