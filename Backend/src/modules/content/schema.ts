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
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../auth/schema.js";

export const contentResourceType = applicationSchema.enum("content_resource_type", [
  "character",
  "conversation",
  "favorite",
  "memory",
  "message",
  "quiz_record",
  "story_progress",
]);

export const contentRecords = applicationSchema.table(
  "content_records",
  {
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
    parentId: text("parent_id"),
    payload: jsonb("payload").notNull(),
    resourceId: text("resource_id").notNull(),
    resourceType: contentResourceType("resource_type").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    version: integer("version").default(1).notNull(),
  },
  (table) => [
    primaryKey({
      columns: [table.userId, table.resourceType, table.resourceId],
      name: "content_records_primary",
    }),
    check(
      "content_records_resource_id_length",
      sql`length(${table.resourceId}) between 1 and 128`,
    ),
    check("content_records_version_positive", sql`${table.version} >= 1`),
    check(
      "content_records_payload_size",
      sql`octet_length(${table.payload}::text) <= 131072`,
    ),
    index("content_records_user_parent_index").on(
      table.userId,
      table.parentId,
      table.resourceType,
    ),
    index("content_records_user_updated_index").on(table.userId, table.updatedAt),
  ],
);
