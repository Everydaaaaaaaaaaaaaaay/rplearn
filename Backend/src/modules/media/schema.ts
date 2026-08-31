import { sql } from "drizzle-orm";
import { bigint, check, index, text, timestamp, uuid } from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";

export const mediaStatus = applicationSchema.enum("media_status", [
  "pending",
  "ready",
  "deleted",
]);

export const mediaAssets = applicationSchema.table(
  "media_assets",
  {
    byteSize: bigint("byte_size", { mode: "number" }).notNull(),
    checksumSha256: text("checksum_sha256").notNull(),
    contentType: text("content_type").notNull(),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    deletedAt: timestamp("deleted_at", {
      mode: "date",
      withTimezone: true,
    }),
    id: uuid("id").primaryKey(),
    objectKey: text("object_key").notNull().unique(),
    pendingExpiresAt: timestamp("pending_expires_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    purgedAt: timestamp("purged_at", {
      mode: "date",
      withTimezone: true,
    }),
    purpose: text("purpose").notNull(),
    readyAt: timestamp("ready_at", {
      mode: "date",
      withTimezone: true,
    }),
    status: mediaStatus("status").default("pending").notNull(),
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
    check("media_assets_byte_size_positive", sql`${table.byteSize} > 0`),
    check(
      "media_assets_checksum_sha256_length",
      sql`length(${table.checksumSha256}) = 44`,
    ),
    check(
      "media_assets_content_type_allowed",
      sql`${table.contentType} in (
        'audio/aac',
        'audio/caf',
        'audio/mp4',
        'audio/mpeg',
        'audio/wav',
        'audio/x-caf'
      )`,
    ),
    check("media_assets_purpose_allowed", sql`${table.purpose} in ('voice_message')`),
    index("media_assets_user_status_index").on(
      table.userId,
      table.status,
      table.createdAt,
    ),
    index("media_assets_pending_expiry_index")
      .on(table.pendingExpiresAt)
      .where(sql`${table.status} = 'pending'`),
    index("media_assets_purged_retention_index")
      .on(table.purgedAt)
      .where(sql`${table.status} = 'deleted' and ${table.purgedAt} is not null`),
  ],
);
