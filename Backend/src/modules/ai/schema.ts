import { sql } from "drizzle-orm";
import {
  boolean,
  char,
  check,
  date,
  index,
  integer,
  jsonb,
  numeric,
  primaryKey,
  real,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";

export const aiProvider = applicationSchema.enum("ai_provider", [
  "deepseek",
  "openrouter",
  "openai",
  "anthropic",
  "google",
]);

export const aiModelCatalog = applicationSchema.table(
  "ai_model_catalog",
  {
    architecture: jsonb("architecture").default({}).notNull(),
    available: boolean("available").default(true).notNull(),
    cachedInputPriceUsd: numeric("cached_input_price_usd", {
      precision: 30,
      scale: 18,
    }),
    completionPriceUsd: numeric("completion_price_usd", {
      precision: 30,
      scale: 18,
    }).notNull(),
    contextLength: integer("context_length"),
    displayName: text("display_name").notNull(),
    model: text("model").notNull(),
    promptPriceUsd: numeric("prompt_price_usd", {
      precision: 30,
      scale: 18,
    }).notNull(),
    provider: aiProvider("provider").notNull(),
    refreshedAt: timestamp("refreshed_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    supportedParameters: jsonb("supported_parameters").default([]).notNull(),
  },
  (table) => [
    primaryKey({ columns: [table.provider, table.model] }),
    index("ai_model_catalog_provider_name_index").on(table.provider, table.displayName),
    check(
      "ai_model_catalog_context_positive",
      sql`${table.contextLength} is null or ${table.contextLength} > 0`,
    ),
    check(
      "ai_model_catalog_prices_nonnegative",
      sql`${table.promptPriceUsd} >= 0 and ${table.completionPriceUsd} >= 0 and (${table.cachedInputPriceUsd} is null or ${table.cachedInputPriceUsd} >= 0)`,
    ),
  ],
);

export const aiRequestStatus = applicationSchema.enum("ai_request_status", [
  "started",
  "succeeded",
  "failed",
  "cancelled",
]);

export const aiRoutes = applicationSchema.table(
  "ai_routes",
  {
    allowJsonResponse: boolean("allow_json_response").default(false).notNull(),
    configVersion: integer("config_version").default(1).notNull(),
    enabled: boolean("enabled").default(true).notNull(),
    maxInputCharacters: integer("max_input_characters").notNull(),
    maxMessages: integer("max_messages").notNull(),
    maxOutputTokens: integer("max_output_tokens").notNull(),
    model: text("model").notNull(),
    provider: aiProvider("provider").notNull(),
    providerOptions: jsonb("provider_options").default({}).notNull(),
    task: text("task").primaryKey(),
    temperature: real("temperature"),
    timeoutMs: integer("timeout_ms").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    check("ai_routes_config_version_positive", sql`${table.configVersion} >= 1`),
    check("ai_routes_max_messages_positive", sql`${table.maxMessages} >= 1`),
    check(
      "ai_routes_max_input_characters_positive",
      sql`${table.maxInputCharacters} >= 1`,
    ),
    check("ai_routes_max_output_tokens_positive", sql`${table.maxOutputTokens} >= 1`),
    check("ai_routes_timeout_positive", sql`${table.timeoutMs} >= 1000`),
    check(
      "ai_routes_temperature_range",
      sql`${table.temperature} is null or
        (${table.temperature} >= 0 and ${table.temperature} <= 2)`,
    ),
  ],
);

export const aiDailyUsage = applicationSchema.table(
  "ai_daily_usage",
  {
    inputTokens: integer("input_tokens").default(0).notNull(),
    outputTokens: integer("output_tokens").default(0).notNull(),
    quotaLimit: integer("quota_limit").notNull(),
    requestCount: integer("request_count").default(0).notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    usageDate: date("usage_date", { mode: "string" }).notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.usageDate],
      name: "ai_daily_usage_user_date_pk",
    }),
    check("ai_daily_usage_request_nonnegative", sql`${table.requestCount} >= 0`),
    check("ai_daily_usage_input_nonnegative", sql`${table.inputTokens} >= 0`),
    check("ai_daily_usage_output_nonnegative", sql`${table.outputTokens} >= 0`),
    check("ai_daily_usage_quota_positive", sql`${table.quotaLimit} >= 1`),
  ],
);

/// Development guest identities are deliberately separate from registered
/// identities. They can consume the AI free tier, but cannot authenticate to
/// account, sync, billing, or media routes.
export const aiGuestPrincipals = applicationSchema.table(
  "ai_guest_principals",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    deviceReference: char("device_reference", { length: 64 }).notNull(),
    lastSeenAt: timestamp("last_seen_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .primaryKey()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    uniqueIndex("ai_guest_principals_device_unique").on(table.deviceReference),
  ],
);

export const aiRouteRevisions = applicationSchema.table(
  "ai_route_revisions",
  {
    changedAt: timestamp("changed_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    changeReason: text("change_reason").notNull(),
    commandId: uuid("command_id").notNull(),
    configVersion: integer("config_version").notNull(),
    id: uuid("id").primaryKey(),
    newConfig: jsonb("new_config").notNull(),
    operatorKeyId: text("operator_key_id").notNull(),
    previousConfig: jsonb("previous_config").notNull(),
    requestHash: text("request_hash").notNull(),
    task: text("task")
      .notNull()
      .references(() => aiRoutes.task, { onDelete: "restrict" }),
  },
  (table) => [
    check(
      "ai_route_revisions_config_version_positive",
      sql`${table.configVersion} >= 1`,
    ),
    uniqueIndex("ai_route_revisions_command_unique").on(table.commandId),
    uniqueIndex("ai_route_revisions_task_version_unique").on(
      table.task,
      table.configVersion,
    ),
    index("ai_route_revisions_task_time_index").on(table.task, table.changedAt),
  ],
);

export const aiRequests = applicationSchema.table(
  "ai_requests",
  {
    operationId: uuid("operation_id"),
    providerAttempts: integer("provider_attempts").default(0).notNull(),
    cacheHitTokens: integer("cache_hit_tokens"),
    cacheMissTokens: integer("cache_miss_tokens"),
    completedAt: timestamp("completed_at", {
      mode: "date",
      withTimezone: true,
    }),
    configVersion: integer("config_version").notNull(),
    errorCode: text("error_code"),
    id: uuid("id").primaryKey(),
    inputCharacters: integer("input_characters").notNull(),
    inputTokens: integer("input_tokens"),
    latencyMs: integer("latency_ms"),
    model: text("model").notNull(),
    outputTokens: integer("output_tokens"),
    providerCostUsd: numeric("provider_cost_usd", { precision: 24, scale: 12 }),
    provider: aiProvider("provider").notNull(),
    requestedAt: timestamp("requested_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    status: aiRequestStatus("status").default("started").notNull(),
    task: text("task").notNull(),
    upstreamRequestId: text("upstream_request_id"),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    check(
      "ai_requests_input_characters_nonnegative",
      sql`${table.inputCharacters} >= 0`,
    ),
    check(
      "ai_requests_input_tokens_nonnegative",
      sql`${table.inputTokens} is null or ${table.inputTokens} >= 0`,
    ),
    check(
      "ai_requests_output_tokens_nonnegative",
      sql`${table.outputTokens} is null or ${table.outputTokens} >= 0`,
    ),
    check(
      "ai_requests_provider_cost_nonnegative",
      sql`${table.providerCostUsd} is null or ${table.providerCostUsd} >= 0`,
    ),
    check(
      "ai_requests_latency_nonnegative",
      sql`${table.latencyMs} is null or ${table.latencyMs} >= 0`,
    ),
    index("ai_requests_user_time_index").on(table.userId, table.requestedAt),
    index("ai_requests_status_time_index").on(table.status, table.requestedAt),
  ],
);
