import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  numeric,
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

// Monetary history is separate from legacy request counts. Never reinterpret old amounts.
export const creditOperations = applicationSchema.table(
  "credit_operations",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    operationId: uuid("operation_id").notNull(),
    parentOperationId: uuid("parent_operation_id"),
    requestHash: text("request_hash").notNull(),
    task: text("task").notNull(),
    billingScope: text("billing_scope").default("user").notNull(),
    plan: text("plan").notNull(),
    windowKey: text("window_key").notNull(),
    policyVersion: text("policy_version").notNull(),
    reservedUnits: numeric("reserved_units", { precision: 24, scale: 0 }).notNull(),
    settledUnits: numeric("settled_units", { precision: 24, scale: 0 }),
    status: text("status").notNull(),
    price: jsonb("price").notNull(),
    usage: jsonb("usage"),
    providerRequestId: text("provider_request_id"),
    result: jsonb("result"),
    reason: text("reason"),
    reconciliation: jsonb("reconciliation"),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
    expiresAt: timestamp("expires_at", { withTimezone: true }).notNull(),
    dispatchedAt: timestamp("dispatched_at", { withTimezone: true }),
    completedAt: timestamp("completed_at", { withTimezone: true }),
  },
  (table) => [
    primaryKey({ columns: [table.userId, table.operationId] }),
    index("credit_operations_balance").on(table.userId, table.windowKey, table.status),
    index("credit_operations_recent").on(table.userId, table.createdAt.desc()),
    index("credit_operations_unresolved")
      .on(table.userId)
      .where(
        sql`${table.status} in ('reserved','dispatched','pending') or (${table.settledUnits}>${table.reservedUnits} and ${table.reconciliation} is null)`,
      ),
    uniqueIndex("credit_operations_one_repair")
      .on(table.userId, table.parentOperationId)
      .where(sql`${table.parentOperationId} is not null`),
    check("credit_operations_reserved_units_check", sql`${table.reservedUnits} >= 0`),
    check("credit_operations_settled_units_check", sql`${table.settledUnits} >= 0`),
    check(
      "credit_operations_billing_scope_check",
      sql`${table.billingScope} in ('user','service')`,
    ),
    check(
      "credit_operations_status_check",
      sql`${table.status} in ('reserved','dispatched','pending','settled','released')`,
    ),
  ],
);
