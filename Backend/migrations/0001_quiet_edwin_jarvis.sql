CREATE TYPE "app"."auth_action_type" AS ENUM('email_verification', 'password_reset');--> statement-breakpoint
CREATE TYPE "app"."identity_provider" AS ENUM('email', 'apple', 'google');--> statement-breakpoint
CREATE TYPE "app"."session_platform" AS ENUM('ios', 'android', 'web', 'macos', 'unknown');--> statement-breakpoint
CREATE TYPE "app"."session_status" AS ENUM('active', 'revoked', 'compromised');--> statement-breakpoint
CREATE TYPE "app"."user_status" AS ENUM('active', 'locked', 'pending_deletion');--> statement-breakpoint
CREATE TABLE "app"."auth_action_tokens" (
	"consumed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"token_hash" char(64) NOT NULL,
	"type" "app"."auth_action_type" NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."auth_security_events" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"event_type" text NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"ip_hash" char(64),
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"session_id" uuid,
	"user_id" uuid
);
--> statement-breakpoint
CREATE TABLE "app"."device_sessions" (
	"app_version" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"device_id" text NOT NULL,
	"device_name" text,
	"id" uuid PRIMARY KEY NOT NULL,
	"ip_hash" char(64),
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"platform" "app"."session_platform" NOT NULL,
	"revoke_reason" text,
	"revoked_at" timestamp with time zone,
	"status" "app"."session_status" DEFAULT 'active' NOT NULL,
	"token_family_id" uuid NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_agent_hash" char(64),
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."refresh_tokens" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"expires_at" timestamp with time zone NOT NULL,
	"family_id" uuid NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"replaced_by_token_id" uuid,
	"revoked_at" timestamp with time zone,
	"session_id" uuid NOT NULL,
	"token_hash" char(64) NOT NULL,
	"used_at" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "app"."user_identities" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"email" text,
	"email_verified_at" timestamp with time zone,
	"id" uuid PRIMARY KEY NOT NULL,
	"password_hash" text,
	"provider" "app"."identity_provider" NOT NULL,
	"provider_subject" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."users" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"last_login_at" timestamp with time zone,
	"status" "app"."user_status" DEFAULT 'active' NOT NULL,
	"token_version" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."auth_action_tokens" ADD CONSTRAINT "auth_action_tokens_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."device_sessions" ADD CONSTRAINT "device_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."refresh_tokens" ADD CONSTRAINT "refresh_tokens_session_id_device_sessions_id_fk" FOREIGN KEY ("session_id") REFERENCES "app"."device_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_identities" ADD CONSTRAINT "user_identities_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "auth_action_tokens_hash_unique" ON "app"."auth_action_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "auth_action_tokens_user_type_index" ON "app"."auth_action_tokens" USING btree ("user_id","type");--> statement-breakpoint
CREATE INDEX "auth_action_tokens_expiry_index" ON "app"."auth_action_tokens" USING btree ("expires_at") WHERE "app"."auth_action_tokens"."consumed_at" is null;--> statement-breakpoint
CREATE INDEX "auth_security_events_user_created_index" ON "app"."auth_security_events" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "auth_security_events_type_created_index" ON "app"."auth_security_events" USING btree ("event_type","created_at");--> statement-breakpoint
CREATE INDEX "device_sessions_user_id_index" ON "app"."device_sessions" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "device_sessions_user_device_index" ON "app"."device_sessions" USING btree ("user_id","device_id");--> statement-breakpoint
CREATE UNIQUE INDEX "device_sessions_family_unique" ON "app"."device_sessions" USING btree ("token_family_id");--> statement-breakpoint
CREATE UNIQUE INDEX "refresh_tokens_hash_unique" ON "app"."refresh_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "refresh_tokens_session_index" ON "app"."refresh_tokens" USING btree ("session_id");--> statement-breakpoint
CREATE INDEX "refresh_tokens_family_index" ON "app"."refresh_tokens" USING btree ("family_id");--> statement-breakpoint
CREATE INDEX "refresh_tokens_expiry_index" ON "app"."refresh_tokens" USING btree ("expires_at");--> statement-breakpoint
CREATE UNIQUE INDEX "user_identities_provider_subject_unique" ON "app"."user_identities" USING btree ("provider","provider_subject");--> statement-breakpoint
CREATE INDEX "user_identities_user_id_index" ON "app"."user_identities" USING btree ("user_id");