import { sql } from "drizzle-orm";
import {
  boolean,
  check,
  index,
  integer,
  jsonb,
  primaryKey,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";
import type {
  AvatarProfile,
  AvatarRequirements,
  NpcDiversityProfile,
  RegisterPublicNpcInput,
} from "./types.js";

export const npcRelationshipStatus = applicationSchema.enum("npc_relationship_status", [
  "candidate",
  "friend",
  "removed",
]);

/// Pre-generated artwork metadata. Binary images live behind HTTPS/object storage.
export const npcAvatars = applicationSchema.table(
  "npc_avatars",
  {
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    enabled: boolean("enabled").default(true).notNull(),
    id: uuid("id").primaryKey(),
    imageUrl: text("image_url").notNull(),
    tags: jsonb("tags").$type<readonly string[]>().default([]).notNull(),
    profile: jsonb("profile").$type<AvatarProfile | null>(),
    updatedAt: timestamp("updated_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("npc_avatars_image_url_unique").on(table.imageUrl),
    index("npc_avatars_enabled_index").on(table.enabled, table.createdAt),
    check(
      "npc_avatars_https_url",
      sql`${table.imageUrl} ~ '^https://[^[:space:]]+$' and octet_length(${table.imageUrl}) <= 2048`,
    ),
    check("npc_avatars_tags_size", sql`octet_length(${table.tags}::text) <= 4096`),
  ],
);

/// Shared immutable identity. User-specific friendship, memories and growth never live here.
export const publicNpcs = applicationSchema.table(
  "public_npcs",
  {
    avatarId: uuid("avatar_id").references(() => npcAvatars.id, {
      onDelete: "set null",
    }),
    card: jsonb("card").notNull(),
    cardHash: text("card_hash").notNull(),
    personaProfile: jsonb("persona_profile").$type<NpcDiversityProfile | null>(),
    personaSignature: text("persona_signature"),
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    createdByUserId: uuid("created_by_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    id: uuid("id").primaryKey(),
    travelerId: text("traveler_id").notNull(),
    updatedAt: timestamp("updated_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    uniqueIndex("public_npcs_traveler_id_unique").on(table.travelerId),
    uniqueIndex("public_npcs_persona_signature_unique").on(table.personaSignature),
    index("public_npcs_avatar_id_index").on(table.avatarId),
    index("public_npcs_region_id_index").on(sql`(${table.card}->>'regionId')`),
    index("public_npcs_creator_index").on(table.createdByUserId, table.createdAt),
    check("public_npcs_traveler_id_format", sql`${table.travelerId} ~ '^[0-9]{11}$'`),
    check("public_npcs_card_hash_format", sql`${table.cardHash} ~ '^[0-9a-f]{64}$'`),
    check(
      "public_npcs_persona_signature_format",
      sql`${table.personaSignature} is null or ${table.personaSignature} ~ '^[0-9a-f]{64}$'`,
    ),
    check(
      "public_npcs_persona_profile_size",
      sql`${table.personaProfile} is null or octet_length(${table.personaProfile}::text) <= 4096`,
    ),
    check("public_npcs_card_size", sql`octet_length(${table.card}::text) <= 32768`),
  ],
);

/// Structured coverage evidence, without names, story text or nationality.
export const npcAvatarMatchEvents = applicationSchema.table(
  "npc_avatar_match_events",
  {
    npcId: uuid("npc_id").notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    requirements: jsonb("requirements").$type<AvatarRequirements>().notNull(),
    reason: text("reason").notNull(),
    eligibleCount: integer("eligible_count").notNull(),
    unseenCount: integer("unseen_count").notNull(),
    selectedAvatarId: uuid("selected_avatar_id").references(() => npcAvatars.id),
    updatedAt: timestamp("updated_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [primaryKey({ columns: [table.userId, table.npcId] })],
);

/// Maps a shared NPC identity to one user's private local relationship branch.
export const userNpcRelationships = applicationSchema.table(
  "user_npc_relationships",
  {
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    localCharacterId: uuid("local_character_id").notNull(),
    npcId: uuid("npc_id")
      .notNull()
      .references(() => publicNpcs.id, { onDelete: "cascade" }),
    status: npcRelationshipStatus("status").default("candidate").notNull(),
    updatedAt: timestamp("updated_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.npcId],
      name: "user_npc_relationships_primary",
    }),
    uniqueIndex("user_npc_relationships_local_character_unique").on(
      table.userId,
      table.localCharacterId,
    ),
    index("user_npc_relationships_status_index").on(table.userId, table.status),
  ],
);

export const npcLibraryVersions = applicationSchema.table(
  "npc_library_versions",
  {
    version: text("version").primaryKey(),
    manifestHash: text("manifest_hash").notNull(),
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (t) => [
    check(
      "npc_library_versions_manifest_hash_check",
      sql`${t.manifestHash} ~ '^[0-9a-f]{64}$'`,
    ),
  ],
);

export const npcAuthoredEncounterRuns = applicationSchema.table(
  "npc_authored_encounter_runs",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    runId: uuid("run_id").notNull(),
    requestHash: text("request_hash").notNull(),
    selection: jsonb("selection").notNull(),
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (t) => [
    primaryKey({ columns: [t.userId, t.runId] }),
    check(
      "npc_authored_encounter_runs_request_hash_check",
      sql`${t.requestHash} ~ '^[0-9a-f]{64}$'`,
    ),
    check(
      "npc_authored_encounter_runs_selection_check",
      sql`octet_length(${t.selection}::text) <= 65536`,
    ),
  ],
);

export const npcSceneAffinities = applicationSchema.table(
  "npc_scene_affinities",
  {
    npcId: uuid("npc_id")
      .notNull()
      .references(() => publicNpcs.id, { onDelete: "cascade" }),
    regionId: text("region_id").notNull(),
    activityId: text("activity_id").notNull(),
    category: text("category").notNull(),
    language: text("language").notNull(),
    libraryVersion: text("library_version").references(
      () => npcLibraryVersions.version,
    ),
  },
  (t) => [
    primaryKey({ columns: [t.npcId, t.regionId, t.activityId, t.language] }),
    index("npc_scene_lookup").on(t.regionId, t.activityId, t.language),
  ],
);

export const npcEncounterHistory = applicationSchema.table(
  "npc_encounter_history",
  {
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    npcId: uuid("npc_id")
      .notNull()
      .references(() => publicNpcs.id, { onDelete: "cascade" }),
    lastSeenAt: timestamp("last_seen_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    encounters: integer("encounters").default(1).notNull(),
  },
  (t) => [primaryKey({ columns: [t.userId, t.npcId] })],
);

export const npcSceneSupply = applicationSchema.table(
  "npc_scene_supply",
  {
    regionId: text("region_id").notNull(),
    activityId: text("activity_id").notNull(),
    language: text("language").notNull(),
    selections: integer("selections").default(0).notNull(),
    reuses: integer("reuses").default(0).notNull(),
    gaps: integer("gaps").default(0).notNull(),
    candidateCount: integer("candidate_count").default(0).notNull(),
    updatedAt: timestamp("updated_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (t) => [primaryKey({ columns: [t.regionId, t.activityId, t.language] })],
);

/// Durable unmatched registration, preserving the original narrative and hard requirements.
export const npcPendingAvatars = applicationSchema.table(
  "npc_pending_avatars",
  {
    npcId: uuid("npc_id").primaryKey(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    input: jsonb("input").$type<RegisterPublicNpcInput>().notNull(),
    cardHash: text("card_hash").notNull(),
    personaProfile: jsonb("persona_profile").$type<NpcDiversityProfile | null>(),
    personaSignature: text("persona_signature"),
    createdAt: timestamp("created_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
    nextAttemptAt: timestamp("next_attempt_at", { mode: "date", withTimezone: true })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    index("npc_pending_avatars_due_index").on(table.nextAttemptAt, table.npcId),
    index("npc_pending_avatars_user_index").on(table.userId),
    index("npc_pending_avatars_region_id_index").on(
      sql`(${table.input}->'card'->>'regionId')`,
    ),
    uniqueIndex("npc_pending_avatars_persona_signature_unique").on(
      table.personaSignature,
    ),
    check(
      "npc_pending_avatars_input_size",
      sql`octet_length(${table.input}::text) <= 36864`,
    ),
    check("npc_pending_avatars_hash_format", sql`${table.cardHash} ~ '^[0-9a-f]{64}$'`),
    check(
      "npc_pending_avatars_persona_signature_format",
      sql`${table.personaSignature} is null or ${table.personaSignature} ~ '^[0-9a-f]{64}$'`,
    ),
    check(
      "npc_pending_avatars_persona_profile_size",
      sql`${table.personaProfile} is null or octet_length(${table.personaProfile}::text) <= 4096`,
    ),
  ],
);
