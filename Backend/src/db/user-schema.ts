import { integer, timestamp, uuid } from "drizzle-orm/pg-core";
import { applicationSchema } from "./schema.js";

export const userStatus = applicationSchema.enum("user_status", [
  "active",
  "locked",
  "pending_deletion",
]);

export const users = applicationSchema.table("users", {
  createdAt: timestamp("created_at", {
    mode: "date",
    withTimezone: true,
  })
    .defaultNow()
    .notNull(),
  id: uuid("id").primaryKey(),
  lastLoginAt: timestamp("last_login_at", {
    mode: "date",
    withTimezone: true,
  }),
  status: userStatus("status").default("active").notNull(),
  tokenVersion: integer("token_version").default(0).notNull(),
  updatedAt: timestamp("updated_at", {
    mode: "date",
    withTimezone: true,
  })
    .defaultNow()
    .notNull(),
});
