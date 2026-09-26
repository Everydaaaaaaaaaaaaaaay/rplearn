import { sql } from "drizzle-orm";
import {
  primaryKey,
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
import { users } from "../../db/user-schema.js";

export const difficultyLevel = applicationSchema.enum("difficulty_level", [
  "kindergarten",
  "primary1",
  "primary2",
  "primary3",
  "primary4",
  "primary5",
  "primary6",
  "junior1",
  "junior2",
  "junior3",
  "senior1",
  "senior2",
  "senior3",
  "undergraduate",
  "postgraduate",
  "advanced",
]);

export const learningGoal = applicationSchema.enum("learning_goal", [
  "dailyConversation",
  "travel",
  "school",
  "exam",
  "studyAbroad",
  "work",
  "culture",
]);

export const studyStage = applicationSchema.enum("study_stage", [
  "primary",
  "juniorHigh",
  "seniorHigh",
  "university",
  "postgraduate",
  "working",
  "other",
]);

export const proficiencySource = applicationSchema.enum("proficiency_source", [
  "selfReported",
  "placement",
]);

export const ticketType = applicationSchema.enum("ticket_type", [
  "universal",
  "country",
]);

export const ticketSource = applicationSchema.enum("ticket_source", [
  "story",
  "quest",
  "purchase",
  "subscription",
  "support",
  "debug",
]);

export const inventoryStatus = applicationSchema.enum("inventory_status", [
  "available",
  "consumed",
  "revoked",
]);

export const regions = applicationSchema.table("regions", {
  countryCode: text("country_code").notNull(),
  id: text("id").primaryKey(),
  isActive: boolean("is_active").default(true).notNull(),
  nameEn: text("name_en").notNull(),
  nameZh: text("name_zh").notNull(),
});

export const userProfiles = applicationSchema.table(
  "user_profiles",
  {
    coins: integer("coins").default(0).notNull(),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    currentRegionId: text("current_region_id")
      .default("london")
      .notNull()
      .references(() => regions.id),
    difficulty: difficultyLevel("difficulty").default("junior1").notNull(),
    displayName: text("display_name").default("旅行者").notNull(),
    experiencePoints: integer("experience_points").default(0).notNull(),
    friendSlotLimit: integer("friend_slot_limit").default(5).notNull(),
    gameLevel: integer("game_level").default(1).notNull(),
    hasCompletedOnboarding: boolean("has_completed_onboarding")
      .default(false)
      .notNull(),
    hasCompletedProfileSetup: boolean("has_completed_profile_setup")
      .default(false)
      .notNull(),
    learningGoal: learningGoal("learning_goal").default("dailyConversation").notNull(),
    placementCompletedAt: timestamp("placement_completed_at", {
      mode: "date",
      withTimezone: true,
    }),
    placementScore: integer("placement_score"),
    proficiencySource: proficiencySource("proficiency_source")
      .default("selfReported")
      .notNull(),
    starterRegionId: text("starter_region_id").references(() => regions.id),
    studyStage: studyStage("study_stage"),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .primaryKey()
      .references(() => users.id, { onDelete: "cascade" }),
    version: integer("version").default(1).notNull(),
  },
  (table) => [
    check("user_profiles_coins_nonnegative", sql`${table.coins} >= 0`),
    check("user_profiles_experience_nonnegative", sql`${table.experiencePoints} >= 0`),
    check("user_profiles_level_positive", sql`${table.gameLevel} >= 1`),
    check(
      "user_profiles_placement_score_range",
      sql`${table.placementScore} is null or ${table.placementScore} between 0 and 100`,
    ),
    check("user_profiles_version_positive", sql`${table.version} >= 1`),
  ],
);

export const coinLedger = applicationSchema.table(
  "coin_ledger",
  {
    balanceAfter: integer("balance_after").notNull(),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    delta: integer("delta").notNull(),
    id: uuid("id").primaryKey(),
    reason: text("reason").notNull(),
    referenceId: text("reference_id"),
    referenceType: text("reference_type"),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    check("coin_ledger_balance_nonnegative", sql`${table.balanceAfter} >= 0`),
    check("coin_ledger_delta_nonzero", sql`${table.delta} <> 0`),
    index("coin_ledger_user_created_index").on(table.userId, table.createdAt),
    uniqueIndex("coin_ledger_reference_unique")
      .on(table.userId, table.referenceType, table.referenceId)
      .where(sql`${table.referenceId} is not null`),
  ],
);

export const inventoryItems = applicationSchema.table(
  "inventory_items",
  {
    consumedAt: timestamp("consumed_at", {
      mode: "date",
      withTimezone: true,
    }),
    consumedForRegionId: text("consumed_for_region_id").references(() => regions.id),
    countryCode: text("country_code"),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    id: uuid("id").primaryKey(),
    source: ticketSource("source").notNull(),
    sourceReferenceId: text("source_reference_id"),
    status: inventoryStatus("status").default("available").notNull(),
    type: ticketType("type").notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    check(
      "inventory_country_ticket_country_required",
      sql`(${table.type} = 'country' and ${table.countryCode} is not null)
          or (${table.type} = 'universal' and ${table.countryCode} is null)`,
    ),
    index("inventory_user_status_index").on(table.userId, table.status),
    uniqueIndex("inventory_source_reference_unique")
      .on(table.userId, table.source, table.sourceReferenceId)
      .where(sql`${table.sourceReferenceId} is not null`),
  ],
);

export const regionUnlocks = applicationSchema.table(
  "region_unlocks",
  {
    regionId: text("region_id")
      .notNull()
      .references(() => regions.id),
    source: text("source").notNull(),
    unlockedAt: timestamp("unlocked_at", {
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
    uniqueIndex("region_unlocks_user_region_unique").on(table.userId, table.regionId),
    index("region_unlocks_user_time_index").on(table.userId, table.unlockedAt),
  ],
);

export const travelRecords = applicationSchema.table(
  "travel_records",
  {
    fromRegionId: text("from_region_id")
      .notNull()
      .references(() => regions.id),
    id: uuid("id").primaryKey(),
    ticketItemId: uuid("ticket_item_id").references(() => inventoryItems.id),
    toRegionId: text("to_region_id")
      .notNull()
      .references(() => regions.id),
    traveledAt: timestamp("traveled_at", {
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
    index("travel_records_user_time_index").on(table.userId, table.traveledAt),
  ],
);

export const commandReceipts = applicationSchema.table(
  "command_receipts",
  {
    commandId: uuid("command_id").notNull(),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    requestHash: text("request_hash").notNull(),
    response: jsonb("response").notNull(),
    route: text("route").notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    uniqueIndex("command_receipts_user_command_unique").on(
      table.userId,
      table.commandId,
    ),
    index("command_receipts_created_index").on(table.createdAt),
  ],
);

export const storyRewardClaims = applicationSchema.table(
  "story_reward_claims",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    storyId: text("story_id").notNull(),
    rewardCoins: integer("reward_coins").notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.storyId] })],
);
