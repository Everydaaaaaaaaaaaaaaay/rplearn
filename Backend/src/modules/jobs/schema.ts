import { sql } from "drizzle-orm";
import {
  check,
  customType,
  index,
  integer,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";

const binary = customType<{ data: Buffer; driverData: Buffer }>({
  dataType: () => "bytea",
});

export const jobStatus = applicationSchema.enum("job_status", [
  "pending",
  "running",
  "succeeded",
  "dead",
  "cancelled",
]);

export const jobs = applicationSchema.table(
  "jobs",
  {
    attempts: integer("attempts").default(0).notNull(),
    availableAt: timestamp("available_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
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
    keyVersion: text("key_version").notNull(),
    lastError: text("last_error"),
    leaseExpiresAt: timestamp("lease_expires_at", {
      mode: "date",
      withTimezone: true,
    }),
    lockedBy: text("locked_by"),
    maxAttempts: integer("max_attempts").default(8).notNull(),
    nonce: binary("nonce").notNull(),
    payloadCiphertext: binary("payload_ciphertext").notNull(),
    status: jobStatus("status").default("pending").notNull(),
    tag: binary("tag").notNull(),
    type: text("type").notNull(),
    uniqueKey: text("unique_key"),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
  },
  (table) => [
    check("jobs_attempts_nonnegative", sql`${table.attempts} >= 0`),
    check("jobs_max_attempts_positive", sql`${table.maxAttempts} > 0`),
    uniqueIndex("jobs_unique_key_unique")
      .on(table.uniqueKey)
      .where(sql`${table.uniqueKey} is not null`),
    index("jobs_pending_available_index")
      .on(table.availableAt, table.createdAt)
      .where(sql`${table.status} = 'pending'`),
    index("jobs_running_lease_index")
      .on(table.leaseExpiresAt)
      .where(sql`${table.status} = 'running'`),
    index("jobs_user_created_index").on(table.userId, table.createdAt),
    index("jobs_completed_index")
      .on(table.completedAt)
      .where(sql`${table.status} in ('succeeded', 'cancelled')`),
  ],
);
