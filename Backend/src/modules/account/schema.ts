import { sql } from "drizzle-orm";
import { char, index, timestamp, uniqueIndex, uuid } from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../auth/schema.js";

export const accountDeletionStatus = applicationSchema.enum("account_deletion_status", [
  "scheduled",
  "processing",
  "cancelled",
  "completed",
]);

export const accountDeletionRequests = applicationSchema.table(
  "account_deletion_requests",
  {
    cancellationTokenHash: char("cancellation_token_hash", {
      length: 64,
    }),
    cancelledAt: timestamp("cancelled_at", {
      mode: "date",
      withTimezone: true,
    }),
    completedAt: timestamp("completed_at", {
      mode: "date",
      withTimezone: true,
    }),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    id: uuid("id").primaryKey(),
    purgeAt: timestamp("purge_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    status: accountDeletionStatus("status").default("scheduled").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    userReferenceHash: char("user_reference_hash", { length: 64 }).notNull(),
  },
  (table) => [
    uniqueIndex("account_deletions_active_user_unique")
      .on(table.userId)
      .where(sql`${table.status} in ('scheduled', 'processing')`),
    uniqueIndex("account_deletions_cancel_token_unique")
      .on(table.cancellationTokenHash)
      .where(sql`${table.cancellationTokenHash} is not null`),
    index("account_deletions_due_index")
      .on(table.purgeAt)
      .where(sql`${table.status} in ('scheduled', 'processing')`),
    index("account_deletions_reference_index").on(table.userReferenceHash),
  ],
);
