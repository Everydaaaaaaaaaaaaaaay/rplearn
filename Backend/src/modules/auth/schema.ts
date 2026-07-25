import { sql } from "drizzle-orm";
import {
  char,
  customType,
  index,
  integer,
  jsonb,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";

const binary = customType<{ data: Buffer; driverData: Buffer }>({
  dataType: () => "bytea",
});

export const userStatus = applicationSchema.enum("user_status", [
  "active",
  "locked",
  "pending_deletion",
]);

export const identityProvider = applicationSchema.enum("identity_provider", [
  "email",
  "apple",
  "google",
]);

export const sessionPlatform = applicationSchema.enum("session_platform", [
  "ios",
  "android",
  "web",
  "macos",
  "unknown",
]);

export const sessionStatus = applicationSchema.enum("session_status", [
  "active",
  "revoked",
  "compromised",
]);

export const authActionType = applicationSchema.enum("auth_action_type", [
  "email_verification",
  "password_reset",
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

export const userIdentities = applicationSchema.table(
  "user_identities",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    email: text("email"),
    emailVerifiedAt: timestamp("email_verified_at", {
      mode: "date",
      withTimezone: true,
    }),
    id: uuid("id").primaryKey(),
    passwordHash: text("password_hash"),
    provider: identityProvider("provider").notNull(),
    providerSubject: text("provider_subject").notNull(),
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
    uniqueIndex("user_identities_provider_subject_unique").on(
      table.provider,
      table.providerSubject,
    ),
    index("user_identities_user_id_index").on(table.userId),
  ],
);

export const deviceSessions = applicationSchema.table(
  "device_sessions",
  {
    appVersion: text("app_version"),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    deviceId: text("device_id").notNull(),
    deviceName: text("device_name"),
    id: uuid("id").primaryKey(),
    ipHash: char("ip_hash", { length: 64 }),
    lastSeenAt: timestamp("last_seen_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    platform: sessionPlatform("platform").notNull(),
    revokeReason: text("revoke_reason"),
    revokedAt: timestamp("revoked_at", {
      mode: "date",
      withTimezone: true,
    }),
    status: sessionStatus("status").default("active").notNull(),
    tokenFamilyId: uuid("token_family_id").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    userAgentHash: char("user_agent_hash", { length: 64 }),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    index("device_sessions_user_id_index").on(table.userId),
    index("device_sessions_user_device_index").on(table.userId, table.deviceId),
    uniqueIndex("device_sessions_family_unique").on(table.tokenFamilyId),
  ],
);

export const refreshTokens = applicationSchema.table(
  "refresh_tokens",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    expiresAt: timestamp("expires_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    familyId: uuid("family_id").notNull(),
    id: uuid("id").primaryKey(),
    replacedByTokenId: uuid("replaced_by_token_id"),
    revokedAt: timestamp("revoked_at", {
      mode: "date",
      withTimezone: true,
    }),
    sessionId: uuid("session_id")
      .notNull()
      .references(() => deviceSessions.id, { onDelete: "cascade" }),
    tokenHash: char("token_hash", { length: 64 }).notNull(),
    usedAt: timestamp("used_at", {
      mode: "date",
      withTimezone: true,
    }),
  },
  (table) => [
    uniqueIndex("refresh_tokens_hash_unique").on(table.tokenHash),
    index("refresh_tokens_session_index").on(table.sessionId),
    index("refresh_tokens_family_index").on(table.familyId),
    index("refresh_tokens_expiry_index").on(table.expiresAt),
  ],
);

export const authActionTokens = applicationSchema.table(
  "auth_action_tokens",
  {
    consumedAt: timestamp("consumed_at", {
      mode: "date",
      withTimezone: true,
    }),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    expiresAt: timestamp("expires_at", {
      mode: "date",
      withTimezone: true,
    }).notNull(),
    id: uuid("id").primaryKey(),
    tokenHash: char("token_hash", { length: 64 }).notNull(),
    type: authActionType("type").notNull(),
    userId: uuid("user_id")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
  },
  (table) => [
    uniqueIndex("auth_action_tokens_hash_unique").on(table.tokenHash),
    index("auth_action_tokens_user_type_index").on(table.userId, table.type),
    index("auth_action_tokens_expiry_index")
      .on(table.expiresAt)
      .where(sql`${table.consumedAt} is null`),
  ],
);

export const authSecurityEvents = applicationSchema.table(
  "auth_security_events",
  {
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    eventType: text("event_type").notNull(),
    id: uuid("id").primaryKey(),
    ipHash: char("ip_hash", { length: 64 }),
    metadata: jsonb("metadata").default({}).notNull(),
    sessionId: uuid("session_id"),
    userId: uuid("user_id"),
  },
  (table) => [
    index("auth_security_events_user_created_index").on(table.userId, table.createdAt),
    index("auth_security_events_type_created_index").on(
      table.eventType,
      table.createdAt,
    ),
  ],
);

export const identityProviderCredentials = applicationSchema.table(
  "identity_provider_credentials",
  {
    ciphertext: binary("ciphertext").notNull(),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    identityId: uuid("identity_id")
      .primaryKey()
      .references(() => userIdentities.id, { onDelete: "cascade" }),
    keyVersion: text("key_version").notNull(),
    providerClientId: text("provider_client_id"),
    nonce: binary("nonce").notNull(),
    tag: binary("tag").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [index("identity_credentials_key_version_index").on(table.keyVersion)],
);
