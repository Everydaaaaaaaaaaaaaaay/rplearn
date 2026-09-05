import { sql } from "drizzle-orm";
import {
  boolean,
  check,
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
    uniqueIndex("public_npcs_avatar_id_unique")
      .on(table.avatarId)
      .where(sql`${table.avatarId} is not null`),
    index("public_npcs_creator_index").on(table.createdByUserId, table.createdAt),
    check("public_npcs_traveler_id_format", sql`${table.travelerId} ~ '^[0-9]{11}$'`),
    check("public_npcs_card_hash_format", sql`${table.cardHash} ~ '^[0-9a-f]{64}$'`),
    check("public_npcs_card_size", sql`octet_length(${table.card}::text) <= 32768`),
  ],
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
