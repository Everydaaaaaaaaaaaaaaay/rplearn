import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  jsonb,
  primaryKey,
  text,
  timestamp,
  uuid,
  uniqueIndex,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";
export const usageOperations = applicationSchema.table(
  "usage_operations",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    operationId: uuid("operation_id").notNull(),
    parentOperationId: uuid("parent_operation_id"),
    requestHash: text("request_hash").notNull(),
    kind: text("kind").notNull(),
    windowKey: text("window_key").notNull(),
    plan: text("plan").notNull(),
    policyVersion: integer("policy_version").notNull(),
    amount: integer("amount").notNull(),
    settledAmount: integer("settled_amount"),
    status: text("status").notNull(),
    result: jsonb("result"),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    completedAt: timestamp("completed_at", { withTimezone: true }),
  },
  (table) => [
    uniqueIndex("usage_operations_one_repair")
      .on(table.userId, table.parentOperationId)
      .where(sql`${table.parentOperationId} is not null`),
    primaryKey({ columns: [table.userId, table.operationId] }),
    index("usage_operations_balance").on(
      table.userId,
      table.windowKey,
      table.kind,
      table.status,
    ),
    check(
      "usage_operations_kind_check",
      sql`${table.kind} in ('chat','advanced','auxiliary','voice')`,
    ),
    check("usage_operations_amount_check", sql`${table.amount} > 0`),
    check(
      "usage_operations_settled_amount_check",
      sql`${table.settledAmount} >= 0 and ${table.settledAmount} <= ${table.amount}`,
    ),
    check(
      "usage_operations_status_check",
      sql`${table.status} in ('reserved','succeeded','failed')`,
    ),
  ],
);
