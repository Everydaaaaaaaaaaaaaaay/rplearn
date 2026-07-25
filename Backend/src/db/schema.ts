import { jsonb, pgSchema, text, timestamp } from "drizzle-orm/pg-core";

export const applicationSchema = pgSchema("app");

export const serviceMetadata = applicationSchema.table("service_metadata", {
  createdAt: timestamp("created_at", {
    mode: "date",
    withTimezone: true,
  })
    .defaultNow()
    .notNull(),
  key: text("key").primaryKey(),
  updatedAt: timestamp("updated_at", {
    mode: "date",
    withTimezone: true,
  })
    .defaultNow()
    .notNull(),
  value: jsonb("value").notNull(),
});
