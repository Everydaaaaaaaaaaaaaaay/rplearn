import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  index,
  integer,
  jsonb,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../auth/schema.js";

export const billingProvider = applicationSchema.enum("billing_provider", [
  "apple",
  "google_play",
  "stripe",
  "manual",
]);

export const billingEnvironment = applicationSchema.enum("billing_environment", [
  "sandbox",
  "production",
  "test",
]);

export const subscriptionTier = applicationSchema.enum("subscription_tier", [
  "free",
  "plus",
  "pro",
]);

export const entitlementStatus = applicationSchema.enum("entitlement_status", [
  "active",
  "grace",
  "billing_retry",
  "expired",
  "revoked",
]);

export const billingPlans = applicationSchema.table(
  "billing_plans",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    displayName: text("display_name").notNull(),
    featureFlags: jsonb("feature_flags").notNull(),
    id: text("id").primaryKey(),
    isActive: boolean("is_active").default(true).notNull(),
    rank: integer("rank").notNull(),
    tier: subscriptionTier("tier").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    check("billing_plans_rank_nonnegative", sql`${table.rank} >= 0`),
    uniqueIndex("billing_plans_tier_unique").on(table.tier),
  ],
);

export const storeProducts = applicationSchema.table(
  "store_products",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    isActive: boolean("is_active").default(true).notNull(),
    planId: text("plan_id")
      .notNull()
      .references(() => billingPlans.id),
    productId: text("product_id").notNull(),
    provider: billingProvider("provider").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("store_products_provider_product_unique").on(
      table.provider,
      table.productId,
    ),
    index("store_products_plan_index").on(table.planId),
  ],
);

export const billingTransactions = applicationSchema.table(
  "billing_transactions",
  {
    appAccountToken: uuid("app_account_token"),
    environment: billingEnvironment("environment").notNull(),
    expiresAt: timestamp("expires_at", {
      mode: "date",
      withTimezone: true,
    }),
    id: uuid("id").primaryKey(),
    originalTransactionId: text("original_transaction_id").notNull(),
    ownershipType: text("ownership_type"),
    planId: text("plan_id")
      .notNull()
      .references(() => billingPlans.id),
    productId: text("product_id").notNull(),
    provider: billingProvider("provider").notNull(),
    purchasedAt: timestamp("purchased_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    rawPayload: jsonb("raw_payload").notNull(),
    revokedAt: timestamp("revoked_at", {
      mode: "date",
      withTimezone: true,
    }),
    signedAt: timestamp("signed_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    transactionId: text("transaction_id").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    verifiedAt: timestamp("verified_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("billing_transactions_provider_transaction_unique").on(
      table.provider,
      table.environment,
      table.transactionId,
    ),
    index("billing_transactions_original_index").on(
      table.provider,
      table.environment,
      table.originalTransactionId,
    ),
    index("billing_transactions_user_time_index").on(table.userId, table.purchasedAt),
  ],
);

export const subscriptions = applicationSchema.table(
  "subscriptions",
  {
    autoRenewEnabled: boolean("auto_renew_enabled"),
    environment: billingEnvironment("environment").notNull(),
    expiresAt: timestamp("expires_at", {
      mode: "date",
      withTimezone: true,
    }),
    gracePeriodExpiresAt: timestamp("grace_period_expires_at", {
      mode: "date",
      withTimezone: true,
    }),
    id: uuid("id").primaryKey(),
    latestTransactionId: text("latest_transaction_id").notNull(),
    originalTransactionId: text("original_transaction_id").notNull(),
    planId: text("plan_id")
      .notNull()
      .references(() => billingPlans.id),
    productId: text("product_id").notNull(),
    provider: billingProvider("provider").notNull(),
    providerEventAt: timestamp("provider_event_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    providerStatus: integer("provider_status"),
    status: entitlementStatus("status").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    uniqueIndex("subscriptions_provider_original_unique").on(
      table.provider,
      table.environment,
      table.originalTransactionId,
    ),
    index("subscriptions_user_status_index").on(table.userId, table.status),
  ],
);

export const entitlementGrants = applicationSchema.table(
  "entitlement_grants",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    entitlementKey: text("entitlement_key").notNull(),
    environment: billingEnvironment("environment").notNull(),
    id: uuid("id").primaryKey(),
    planId: text("plan_id")
      .notNull()
      .references(() => billingPlans.id),
    providerEventAt: timestamp("provider_event_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    sourceProvider: billingProvider("source_provider").notNull(),
    sourceReferenceId: text("source_reference_id").notNull(),
    status: entitlementStatus("status").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    validUntil: timestamp("valid_until", {
      mode: "date",
      withTimezone: true,
    }),
  },
  (table) => [
    uniqueIndex("entitlement_grants_source_unique").on(
      table.sourceProvider,
      table.environment,
      table.sourceReferenceId,
      table.entitlementKey,
    ),
    index("entitlement_grants_user_status_index").on(table.userId, table.status),
  ],
);

export const billingProviderEvents = applicationSchema.table(
  "billing_provider_events",
  {
    decodedPayload: jsonb("decoded_payload").notNull(),
    environment: billingEnvironment("environment").notNull(),
    eventId: text("event_id").notNull(),
    eventType: text("event_type").notNull(),
    payloadHash: text("payload_hash").notNull(),
    processedAt: timestamp("processed_at", {
      mode: "date",
      withTimezone: true,
    }),
    processingError: text("processing_error"),
    provider: billingProvider("provider").notNull(),
    receivedAt: timestamp("received_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    signedAt: timestamp("signed_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    subtype: text("subtype"),
    userId: uuid("user_id").references(() => users.id, {
      onDelete: "set null",
    }),
  },
  (table) => [
    uniqueIndex("billing_provider_events_identity_unique").on(
      table.provider,
      table.environment,
      table.eventId,
    ),
    index("billing_provider_events_received_index").on(table.receivedAt),
    index("billing_provider_events_unprocessed_index")
      .on(table.provider, table.receivedAt)
      .where(sql`${table.processedAt} is null`),
  ],
);
