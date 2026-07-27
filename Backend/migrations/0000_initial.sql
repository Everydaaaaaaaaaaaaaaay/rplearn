-- LingoTrip development baseline. Recreate the database instead of preserving pre-release history.
CREATE SCHEMA "app";
--> statement-breakpoint
CREATE TYPE "app"."account_deletion_status" AS ENUM('scheduled', 'processing', 'cancelled', 'completed');--> statement-breakpoint
CREATE TYPE "app"."ai_provider" AS ENUM('deepseek', 'openai', 'anthropic', 'google');--> statement-breakpoint
CREATE TYPE "app"."ai_request_status" AS ENUM('started', 'succeeded', 'failed', 'cancelled');--> statement-breakpoint
CREATE TYPE "app"."auth_action_type" AS ENUM('email_verification', 'password_reset');--> statement-breakpoint
CREATE TYPE "app"."identity_provider" AS ENUM('email', 'apple', 'google');--> statement-breakpoint
CREATE TYPE "app"."session_platform" AS ENUM('ios', 'android', 'web', 'macos', 'unknown');--> statement-breakpoint
CREATE TYPE "app"."session_status" AS ENUM('active', 'revoked', 'compromised');--> statement-breakpoint
CREATE TYPE "app"."user_status" AS ENUM('active', 'locked', 'pending_deletion');--> statement-breakpoint
CREATE TYPE "app"."billing_environment" AS ENUM('sandbox', 'production', 'test');--> statement-breakpoint
CREATE TYPE "app"."billing_provider" AS ENUM('apple', 'google_play', 'stripe', 'manual');--> statement-breakpoint
CREATE TYPE "app"."entitlement_status" AS ENUM('active', 'grace', 'billing_retry', 'expired', 'revoked');--> statement-breakpoint
CREATE TYPE "app"."subscription_tier" AS ENUM('free', 'plus', 'pro');--> statement-breakpoint
CREATE TYPE "app"."content_resource_type" AS ENUM('character', 'conversation', 'favorite', 'memory', 'message', 'quiz_record', 'story_progress');--> statement-breakpoint
CREATE TYPE "app"."difficulty_level" AS ENUM('primary1', 'primary2', 'primary3', 'primary4', 'primary5', 'primary6', 'junior1', 'junior2', 'junior3', 'senior1', 'senior2', 'senior3', 'undergraduate', 'postgraduate', 'advanced');--> statement-breakpoint
CREATE TYPE "app"."inventory_status" AS ENUM('available', 'consumed', 'revoked');--> statement-breakpoint
CREATE TYPE "app"."ticket_source" AS ENUM('story', 'quest', 'purchase', 'subscription', 'support', 'debug');--> statement-breakpoint
CREATE TYPE "app"."ticket_type" AS ENUM('universal', 'country');--> statement-breakpoint
CREATE TYPE "app"."job_status" AS ENUM('pending', 'running', 'succeeded', 'dead', 'cancelled');--> statement-breakpoint
CREATE TYPE "app"."media_status" AS ENUM('pending', 'ready', 'deleted');--> statement-breakpoint
CREATE TABLE "app"."service_metadata" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"key" text PRIMARY KEY NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"value" jsonb NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."account_deletion_requests" (
	"cancellation_token_hash" char(64),
	"cancelled_at" timestamp with time zone,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"purge_at" timestamp with time zone NOT NULL,
	"status" "app"."account_deletion_status" DEFAULT 'scheduled' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	"user_reference_hash" char(64) NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."ai_daily_usage" (
	"input_tokens" integer DEFAULT 0 NOT NULL,
	"output_tokens" integer DEFAULT 0 NOT NULL,
	"quota_limit" integer NOT NULL,
	"request_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"usage_date" date NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "ai_daily_usage_user_date_pk" PRIMARY KEY("user_id","usage_date"),
	CONSTRAINT "ai_daily_usage_request_nonnegative" CHECK ("app"."ai_daily_usage"."request_count" >= 0),
	CONSTRAINT "ai_daily_usage_input_nonnegative" CHECK ("app"."ai_daily_usage"."input_tokens" >= 0),
	CONSTRAINT "ai_daily_usage_output_nonnegative" CHECK ("app"."ai_daily_usage"."output_tokens" >= 0),
	CONSTRAINT "ai_daily_usage_quota_positive" CHECK ("app"."ai_daily_usage"."quota_limit" >= 1)
);
--> statement-breakpoint
CREATE TABLE "app"."ai_guest_principals" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"device_reference" char(64) NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid PRIMARY KEY NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."ai_requests" (
	"completed_at" timestamp with time zone,
	"config_version" integer NOT NULL,
	"error_code" text,
	"id" uuid PRIMARY KEY NOT NULL,
	"input_characters" integer NOT NULL,
	"input_tokens" integer,
	"latency_ms" integer,
	"model" text NOT NULL,
	"output_tokens" integer,
	"provider" "app"."ai_provider" NOT NULL,
	"requested_at" timestamp with time zone DEFAULT now() NOT NULL,
	"status" "app"."ai_request_status" DEFAULT 'started' NOT NULL,
	"task" text NOT NULL,
	"upstream_request_id" text,
	"user_id" uuid NOT NULL,
	CONSTRAINT "ai_requests_input_characters_nonnegative" CHECK ("app"."ai_requests"."input_characters" >= 0),
	CONSTRAINT "ai_requests_input_tokens_nonnegative" CHECK ("app"."ai_requests"."input_tokens" is null or "app"."ai_requests"."input_tokens" >= 0),
	CONSTRAINT "ai_requests_output_tokens_nonnegative" CHECK ("app"."ai_requests"."output_tokens" is null or "app"."ai_requests"."output_tokens" >= 0),
	CONSTRAINT "ai_requests_latency_nonnegative" CHECK ("app"."ai_requests"."latency_ms" is null or "app"."ai_requests"."latency_ms" >= 0)
);
--> statement-breakpoint
CREATE TABLE "app"."ai_route_revisions" (
	"changed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"change_reason" text NOT NULL,
	"command_id" uuid NOT NULL,
	"config_version" integer NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"new_config" jsonb NOT NULL,
	"operator_key_id" text NOT NULL,
	"previous_config" jsonb NOT NULL,
	"request_hash" text NOT NULL,
	"task" text NOT NULL,
	CONSTRAINT "ai_route_revisions_config_version_positive" CHECK ("app"."ai_route_revisions"."config_version" >= 1)
);
--> statement-breakpoint
CREATE TABLE "app"."ai_routes" (
	"allow_json_response" boolean DEFAULT false NOT NULL,
	"config_version" integer DEFAULT 1 NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"max_input_characters" integer NOT NULL,
	"max_messages" integer NOT NULL,
	"max_output_tokens" integer NOT NULL,
	"model" text NOT NULL,
	"provider" "app"."ai_provider" NOT NULL,
	"provider_options" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"task" text PRIMARY KEY NOT NULL,
	"temperature" real,
	"timeout_ms" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "ai_routes_config_version_positive" CHECK ("app"."ai_routes"."config_version" >= 1),
	CONSTRAINT "ai_routes_max_messages_positive" CHECK ("app"."ai_routes"."max_messages" >= 1),
	CONSTRAINT "ai_routes_max_input_characters_positive" CHECK ("app"."ai_routes"."max_input_characters" >= 1),
	CONSTRAINT "ai_routes_max_output_tokens_positive" CHECK ("app"."ai_routes"."max_output_tokens" >= 1),
	CONSTRAINT "ai_routes_timeout_positive" CHECK ("app"."ai_routes"."timeout_ms" >= 1000),
	CONSTRAINT "ai_routes_temperature_range" CHECK ("app"."ai_routes"."temperature" is null or
        ("app"."ai_routes"."temperature" >= 0 and "app"."ai_routes"."temperature" <= 2))
);
--> statement-breakpoint
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
CREATE TABLE "app"."identity_provider_credentials" (
	"ciphertext" "bytea" NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"identity_id" uuid PRIMARY KEY NOT NULL,
	"key_version" text NOT NULL,
	"provider_client_id" text,
	"nonce" "bytea" NOT NULL,
	"tag" "bytea" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
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
CREATE TABLE "app"."billing_plans" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"display_name" text NOT NULL,
	"feature_flags" jsonb NOT NULL,
	"id" text PRIMARY KEY NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"rank" integer NOT NULL,
	"tier" "app"."subscription_tier" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "billing_plans_rank_nonnegative" CHECK ("app"."billing_plans"."rank" >= 0)
);
--> statement-breakpoint
CREATE TABLE "app"."billing_provider_events" (
	"decoded_payload" jsonb NOT NULL,
	"environment" "app"."billing_environment" NOT NULL,
	"event_id" text NOT NULL,
	"event_type" text NOT NULL,
	"payload_hash" text NOT NULL,
	"processed_at" timestamp with time zone,
	"processing_error" text,
	"provider" "app"."billing_provider" NOT NULL,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL,
	"signed_at" timestamp with time zone NOT NULL,
	"subtype" text,
	"user_id" uuid
);
--> statement-breakpoint
CREATE TABLE "app"."billing_transactions" (
	"app_account_token" uuid,
	"environment" "app"."billing_environment" NOT NULL,
	"expires_at" timestamp with time zone,
	"id" uuid PRIMARY KEY NOT NULL,
	"original_transaction_id" text NOT NULL,
	"ownership_type" text,
	"plan_id" text NOT NULL,
	"product_id" text NOT NULL,
	"provider" "app"."billing_provider" NOT NULL,
	"purchased_at" timestamp with time zone NOT NULL,
	"raw_payload" jsonb NOT NULL,
	"revoked_at" timestamp with time zone,
	"signed_at" timestamp with time zone NOT NULL,
	"transaction_id" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	"verified_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."entitlement_grants" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"entitlement_key" text NOT NULL,
	"environment" "app"."billing_environment" NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"plan_id" text NOT NULL,
	"provider_event_at" timestamp with time zone NOT NULL,
	"source_provider" "app"."billing_provider" NOT NULL,
	"source_reference_id" text NOT NULL,
	"status" "app"."entitlement_status" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL,
	"valid_until" timestamp with time zone
);
--> statement-breakpoint
CREATE TABLE "app"."store_products" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"plan_id" text NOT NULL,
	"product_id" text NOT NULL,
	"provider" "app"."billing_provider" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."subscriptions" (
	"auto_renew_enabled" boolean,
	"environment" "app"."billing_environment" NOT NULL,
	"expires_at" timestamp with time zone,
	"grace_period_expires_at" timestamp with time zone,
	"id" uuid PRIMARY KEY NOT NULL,
	"latest_transaction_id" text NOT NULL,
	"original_transaction_id" text NOT NULL,
	"plan_id" text NOT NULL,
	"product_id" text NOT NULL,
	"provider" "app"."billing_provider" NOT NULL,
	"provider_event_at" timestamp with time zone NOT NULL,
	"provider_status" integer,
	"reconcile_after" timestamp with time zone DEFAULT now() NOT NULL,
	"reconciliation_attempts" integer DEFAULT 0 NOT NULL,
	"reconciliation_error" text,
	"reconciliation_started_at" timestamp with time zone,
	"last_reconciled_at" timestamp with time zone,
	"status" "app"."entitlement_status" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	CONSTRAINT "subscriptions_reconciliation_attempts_nonnegative" CHECK ("app"."subscriptions"."reconciliation_attempts" >= 0)
);
--> statement-breakpoint
CREATE TABLE "app"."content_records" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	"parent_id" text,
	"payload" jsonb NOT NULL,
	"resource_id" text NOT NULL,
	"resource_type" "app"."content_resource_type" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	CONSTRAINT "content_records_primary" PRIMARY KEY("user_id","resource_type","resource_id"),
	CONSTRAINT "content_records_resource_id_length" CHECK (length("app"."content_records"."resource_id") between 1 and 128),
	CONSTRAINT "content_records_version_positive" CHECK ("app"."content_records"."version" >= 1),
	CONSTRAINT "content_records_payload_size" CHECK (octet_length("app"."content_records"."payload"::text) <= 131072)
);
--> statement-breakpoint
CREATE TABLE "app"."coin_ledger" (
	"balance_after" integer NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"delta" integer NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"reason" text NOT NULL,
	"reference_id" text,
	"reference_type" text,
	"user_id" uuid NOT NULL,
	CONSTRAINT "coin_ledger_balance_nonnegative" CHECK ("app"."coin_ledger"."balance_after" >= 0),
	CONSTRAINT "coin_ledger_delta_nonzero" CHECK ("app"."coin_ledger"."delta" <> 0)
);
--> statement-breakpoint
CREATE TABLE "app"."command_receipts" (
	"command_id" uuid NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"request_hash" text NOT NULL,
	"response" jsonb NOT NULL,
	"route" text NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."inventory_items" (
	"consumed_at" timestamp with time zone,
	"consumed_for_region_id" text,
	"country_code" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"source" "app"."ticket_source" NOT NULL,
	"source_reference_id" text,
	"status" "app"."inventory_status" DEFAULT 'available' NOT NULL,
	"type" "app"."ticket_type" NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "inventory_country_ticket_country_required" CHECK (("app"."inventory_items"."type" = 'country' and "app"."inventory_items"."country_code" is not null)
          or ("app"."inventory_items"."type" = 'universal' and "app"."inventory_items"."country_code" is null))
);
--> statement-breakpoint
CREATE TABLE "app"."region_unlocks" (
	"region_id" text NOT NULL,
	"source" text NOT NULL,
	"unlocked_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."regions" (
	"country_code" text NOT NULL,
	"id" text PRIMARY KEY NOT NULL,
	"is_active" boolean DEFAULT true NOT NULL,
	"name_en" text NOT NULL,
	"name_zh" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."travel_records" (
	"from_region_id" text NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"ticket_item_id" uuid,
	"to_region_id" text NOT NULL,
	"traveled_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."user_profiles" (
	"coins" integer DEFAULT 0 NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"current_region_id" text DEFAULT 'london' NOT NULL,
	"difficulty" "app"."difficulty_level" DEFAULT 'junior1' NOT NULL,
	"display_name" text DEFAULT '旅行者' NOT NULL,
	"experience_points" integer DEFAULT 0 NOT NULL,
	"friend_slot_limit" integer DEFAULT 3 NOT NULL,
	"game_level" integer DEFAULT 1 NOT NULL,
	"has_completed_onboarding" boolean DEFAULT false NOT NULL,
	"quiz_globally_enabled" boolean DEFAULT true NOT NULL,
	"starter_region_id" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid PRIMARY KEY NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	CONSTRAINT "user_profiles_coins_nonnegative" CHECK ("app"."user_profiles"."coins" >= 0),
	CONSTRAINT "user_profiles_experience_nonnegative" CHECK ("app"."user_profiles"."experience_points" >= 0),
	CONSTRAINT "user_profiles_level_positive" CHECK ("app"."user_profiles"."game_level" >= 1),
	CONSTRAINT "user_profiles_version_positive" CHECK ("app"."user_profiles"."version" >= 1)
);
--> statement-breakpoint
CREATE TABLE "app"."jobs" (
	"attempts" integer DEFAULT 0 NOT NULL,
	"available_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"key_version" text NOT NULL,
	"last_error" text,
	"lease_expires_at" timestamp with time zone,
	"locked_by" text,
	"max_attempts" integer DEFAULT 8 NOT NULL,
	"nonce" "bytea" NOT NULL,
	"payload_ciphertext" "bytea" NOT NULL,
	"status" "app"."job_status" DEFAULT 'pending' NOT NULL,
	"tag" "bytea" NOT NULL,
	"type" text NOT NULL,
	"unique_key" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	CONSTRAINT "jobs_attempts_nonnegative" CHECK ("app"."jobs"."attempts" >= 0),
	CONSTRAINT "jobs_max_attempts_positive" CHECK ("app"."jobs"."max_attempts" > 0)
);
--> statement-breakpoint
CREATE TABLE "app"."media_assets" (
	"byte_size" bigint NOT NULL,
	"checksum_sha256" text NOT NULL,
	"content_type" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"deleted_at" timestamp with time zone,
	"id" uuid PRIMARY KEY NOT NULL,
	"object_key" text NOT NULL,
	"pending_expires_at" timestamp with time zone NOT NULL,
	"purged_at" timestamp with time zone,
	"purpose" text NOT NULL,
	"ready_at" timestamp with time zone,
	"status" "app"."media_status" DEFAULT 'pending' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "media_assets_object_key_unique" UNIQUE("object_key"),
	CONSTRAINT "media_assets_byte_size_positive" CHECK ("app"."media_assets"."byte_size" > 0),
	CONSTRAINT "media_assets_checksum_sha256_length" CHECK (length("app"."media_assets"."checksum_sha256") = 44),
	CONSTRAINT "media_assets_content_type_allowed" CHECK ("app"."media_assets"."content_type" in (
        'audio/aac',
        'audio/caf',
        'audio/mp4',
        'audio/mpeg',
        'audio/wav',
        'audio/x-caf'
      )),
	CONSTRAINT "media_assets_purpose_allowed" CHECK ("app"."media_assets"."purpose" in ('voice_message'))
);
--> statement-breakpoint
CREATE TABLE "app"."audit_events" (
	"action" text NOT NULL,
	"actor_kind" text NOT NULL,
	"actor_user_id" uuid,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"ip_hash" text,
	"metadata" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"outcome" text NOT NULL,
	"request_id" text NOT NULL,
	"target_id" text,
	"target_type" text NOT NULL
);
--> statement-breakpoint
CREATE TABLE "app"."sync_changes" (
	"command_id" uuid NOT NULL,
	"event_id" uuid NOT NULL,
	"event_type" text NOT NULL,
	"occurred_at" timestamp with time zone DEFAULT now() NOT NULL,
	"payload" jsonb NOT NULL,
	"sequence" bigint NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "sync_changes_user_sequence_pk" PRIMARY KEY("user_id","sequence")
);
--> statement-breakpoint
CREATE TABLE "app"."sync_heads" (
	"last_sequence" bigint NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid PRIMARY KEY NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."account_deletion_requests" ADD CONSTRAINT "account_deletion_requests_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."ai_daily_usage" ADD CONSTRAINT "ai_daily_usage_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."ai_guest_principals" ADD CONSTRAINT "ai_guest_principals_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."ai_requests" ADD CONSTRAINT "ai_requests_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."ai_route_revisions" ADD CONSTRAINT "ai_route_revisions_task_ai_routes_task_fk" FOREIGN KEY ("task") REFERENCES "app"."ai_routes"("task") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."auth_action_tokens" ADD CONSTRAINT "auth_action_tokens_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."device_sessions" ADD CONSTRAINT "device_sessions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."identity_provider_credentials" ADD CONSTRAINT "identity_provider_credentials_identity_id_user_identities_id_fk" FOREIGN KEY ("identity_id") REFERENCES "app"."user_identities"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."refresh_tokens" ADD CONSTRAINT "refresh_tokens_session_id_device_sessions_id_fk" FOREIGN KEY ("session_id") REFERENCES "app"."device_sessions"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_identities" ADD CONSTRAINT "user_identities_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."billing_provider_events" ADD CONSTRAINT "billing_provider_events_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ADD CONSTRAINT "billing_transactions_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ADD CONSTRAINT "billing_transactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."entitlement_grants" ADD CONSTRAINT "entitlement_grants_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."entitlement_grants" ADD CONSTRAINT "entitlement_grants_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."store_products" ADD CONSTRAINT "store_products_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."content_records" ADD CONSTRAINT "content_records_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."coin_ledger" ADD CONSTRAINT "coin_ledger_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."command_receipts" ADD CONSTRAINT "command_receipts_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."inventory_items" ADD CONSTRAINT "inventory_items_consumed_for_region_id_regions_id_fk" FOREIGN KEY ("consumed_for_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."inventory_items" ADD CONSTRAINT "inventory_items_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."region_unlocks" ADD CONSTRAINT "region_unlocks_region_id_regions_id_fk" FOREIGN KEY ("region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."region_unlocks" ADD CONSTRAINT "region_unlocks_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."travel_records" ADD CONSTRAINT "travel_records_from_region_id_regions_id_fk" FOREIGN KEY ("from_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."travel_records" ADD CONSTRAINT "travel_records_ticket_item_id_inventory_items_id_fk" FOREIGN KEY ("ticket_item_id") REFERENCES "app"."inventory_items"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."travel_records" ADD CONSTRAINT "travel_records_to_region_id_regions_id_fk" FOREIGN KEY ("to_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."travel_records" ADD CONSTRAINT "travel_records_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_current_region_id_regions_id_fk" FOREIGN KEY ("current_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_starter_region_id_regions_id_fk" FOREIGN KEY ("starter_region_id") REFERENCES "app"."regions"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."jobs" ADD CONSTRAINT "jobs_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."media_assets" ADD CONSTRAINT "media_assets_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."audit_events" ADD CONSTRAINT "audit_events_actor_user_id_users_id_fk" FOREIGN KEY ("actor_user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."sync_changes" ADD CONSTRAINT "sync_changes_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."sync_heads" ADD CONSTRAINT "sync_heads_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "account_deletions_active_user_unique" ON "app"."account_deletion_requests" USING btree ("user_id") WHERE "app"."account_deletion_requests"."status" in ('scheduled', 'processing');--> statement-breakpoint
CREATE UNIQUE INDEX "account_deletions_cancel_token_unique" ON "app"."account_deletion_requests" USING btree ("cancellation_token_hash") WHERE "app"."account_deletion_requests"."cancellation_token_hash" is not null;--> statement-breakpoint
CREATE INDEX "account_deletions_due_index" ON "app"."account_deletion_requests" USING btree ("purge_at") WHERE "app"."account_deletion_requests"."status" in ('scheduled', 'processing');--> statement-breakpoint
CREATE INDEX "account_deletions_reference_index" ON "app"."account_deletion_requests" USING btree ("user_reference_hash");--> statement-breakpoint
CREATE UNIQUE INDEX "ai_guest_principals_device_unique" ON "app"."ai_guest_principals" USING btree ("device_reference");--> statement-breakpoint
CREATE INDEX "ai_requests_user_time_index" ON "app"."ai_requests" USING btree ("user_id","requested_at");--> statement-breakpoint
CREATE INDEX "ai_requests_status_time_index" ON "app"."ai_requests" USING btree ("status","requested_at");--> statement-breakpoint
CREATE UNIQUE INDEX "ai_route_revisions_command_unique" ON "app"."ai_route_revisions" USING btree ("command_id");--> statement-breakpoint
CREATE UNIQUE INDEX "ai_route_revisions_task_version_unique" ON "app"."ai_route_revisions" USING btree ("task","config_version");--> statement-breakpoint
CREATE INDEX "ai_route_revisions_task_time_index" ON "app"."ai_route_revisions" USING btree ("task","changed_at");--> statement-breakpoint
CREATE UNIQUE INDEX "auth_action_tokens_hash_unique" ON "app"."auth_action_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "auth_action_tokens_user_type_index" ON "app"."auth_action_tokens" USING btree ("user_id","type");--> statement-breakpoint
CREATE INDEX "auth_action_tokens_expiry_index" ON "app"."auth_action_tokens" USING btree ("expires_at") WHERE "app"."auth_action_tokens"."consumed_at" is null;--> statement-breakpoint
CREATE INDEX "auth_security_events_user_created_index" ON "app"."auth_security_events" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "auth_security_events_type_created_index" ON "app"."auth_security_events" USING btree ("event_type","created_at");--> statement-breakpoint
CREATE INDEX "device_sessions_user_id_index" ON "app"."device_sessions" USING btree ("user_id");--> statement-breakpoint
CREATE INDEX "device_sessions_user_device_index" ON "app"."device_sessions" USING btree ("user_id","device_id");--> statement-breakpoint
CREATE UNIQUE INDEX "device_sessions_family_unique" ON "app"."device_sessions" USING btree ("token_family_id");--> statement-breakpoint
CREATE INDEX "identity_credentials_key_version_index" ON "app"."identity_provider_credentials" USING btree ("key_version");--> statement-breakpoint
CREATE UNIQUE INDEX "refresh_tokens_hash_unique" ON "app"."refresh_tokens" USING btree ("token_hash");--> statement-breakpoint
CREATE INDEX "refresh_tokens_session_index" ON "app"."refresh_tokens" USING btree ("session_id");--> statement-breakpoint
CREATE INDEX "refresh_tokens_family_index" ON "app"."refresh_tokens" USING btree ("family_id");--> statement-breakpoint
CREATE INDEX "refresh_tokens_expiry_index" ON "app"."refresh_tokens" USING btree ("expires_at");--> statement-breakpoint
CREATE UNIQUE INDEX "user_identities_provider_subject_unique" ON "app"."user_identities" USING btree ("provider","provider_subject");--> statement-breakpoint
CREATE INDEX "user_identities_user_id_index" ON "app"."user_identities" USING btree ("user_id");--> statement-breakpoint
CREATE UNIQUE INDEX "billing_plans_tier_unique" ON "app"."billing_plans" USING btree ("tier");--> statement-breakpoint
CREATE UNIQUE INDEX "billing_provider_events_identity_unique" ON "app"."billing_provider_events" USING btree ("provider","environment","event_id");--> statement-breakpoint
CREATE INDEX "billing_provider_events_received_index" ON "app"."billing_provider_events" USING btree ("received_at");--> statement-breakpoint
CREATE INDEX "billing_provider_events_unprocessed_index" ON "app"."billing_provider_events" USING btree ("provider","received_at") WHERE "app"."billing_provider_events"."processed_at" is null;--> statement-breakpoint
CREATE UNIQUE INDEX "billing_transactions_provider_transaction_unique" ON "app"."billing_transactions" USING btree ("provider","environment","transaction_id");--> statement-breakpoint
CREATE INDEX "billing_transactions_original_index" ON "app"."billing_transactions" USING btree ("provider","environment","original_transaction_id");--> statement-breakpoint
CREATE INDEX "billing_transactions_user_time_index" ON "app"."billing_transactions" USING btree ("user_id","purchased_at");--> statement-breakpoint
CREATE UNIQUE INDEX "entitlement_grants_source_unique" ON "app"."entitlement_grants" USING btree ("source_provider","environment","source_reference_id","entitlement_key");--> statement-breakpoint
CREATE INDEX "entitlement_grants_user_status_index" ON "app"."entitlement_grants" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "store_products_provider_product_unique" ON "app"."store_products" USING btree ("provider","product_id");--> statement-breakpoint
CREATE INDEX "store_products_plan_index" ON "app"."store_products" USING btree ("plan_id");--> statement-breakpoint
CREATE UNIQUE INDEX "subscriptions_provider_original_unique" ON "app"."subscriptions" USING btree ("provider","environment","original_transaction_id");--> statement-breakpoint
CREATE INDEX "subscriptions_reconcile_due_index" ON "app"."subscriptions" USING btree ("reconcile_after","updated_at") WHERE "app"."subscriptions"."provider" = 'apple'
          and "app"."subscriptions"."user_id" is not null
          and "app"."subscriptions"."environment" in ('production', 'sandbox');--> statement-breakpoint
CREATE INDEX "subscriptions_user_status_index" ON "app"."subscriptions" USING btree ("user_id","status");--> statement-breakpoint
CREATE INDEX "content_records_user_parent_index" ON "app"."content_records" USING btree ("user_id","parent_id","resource_type");--> statement-breakpoint
CREATE INDEX "content_records_user_updated_index" ON "app"."content_records" USING btree ("user_id","updated_at");--> statement-breakpoint
CREATE INDEX "coin_ledger_user_created_index" ON "app"."coin_ledger" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "coin_ledger_reference_unique" ON "app"."coin_ledger" USING btree ("user_id","reference_type","reference_id") WHERE "app"."coin_ledger"."reference_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "command_receipts_user_command_unique" ON "app"."command_receipts" USING btree ("user_id","command_id");--> statement-breakpoint
CREATE INDEX "command_receipts_created_index" ON "app"."command_receipts" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "inventory_user_status_index" ON "app"."inventory_items" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "inventory_source_reference_unique" ON "app"."inventory_items" USING btree ("user_id","source","source_reference_id") WHERE "app"."inventory_items"."source_reference_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "region_unlocks_user_region_unique" ON "app"."region_unlocks" USING btree ("user_id","region_id");--> statement-breakpoint
CREATE INDEX "region_unlocks_user_time_index" ON "app"."region_unlocks" USING btree ("user_id","unlocked_at");--> statement-breakpoint
CREATE INDEX "travel_records_user_time_index" ON "app"."travel_records" USING btree ("user_id","traveled_at");--> statement-breakpoint
CREATE UNIQUE INDEX "jobs_unique_key_unique" ON "app"."jobs" USING btree ("unique_key") WHERE "app"."jobs"."unique_key" is not null;--> statement-breakpoint
CREATE INDEX "jobs_pending_available_index" ON "app"."jobs" USING btree ("available_at","created_at") WHERE "app"."jobs"."status" = 'pending';--> statement-breakpoint
CREATE INDEX "jobs_running_lease_index" ON "app"."jobs" USING btree ("lease_expires_at") WHERE "app"."jobs"."status" = 'running';--> statement-breakpoint
CREATE INDEX "jobs_user_created_index" ON "app"."jobs" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "jobs_completed_index" ON "app"."jobs" USING btree ("completed_at") WHERE "app"."jobs"."status" in ('succeeded', 'cancelled');--> statement-breakpoint
CREATE INDEX "media_assets_user_status_index" ON "app"."media_assets" USING btree ("user_id","status","created_at");--> statement-breakpoint
CREATE INDEX "media_assets_pending_expiry_index" ON "app"."media_assets" USING btree ("pending_expires_at") WHERE "app"."media_assets"."status" = 'pending';--> statement-breakpoint
CREATE INDEX "media_assets_purged_retention_index" ON "app"."media_assets" USING btree ("purged_at") WHERE "app"."media_assets"."status" = 'deleted' and "app"."media_assets"."purged_at" is not null;--> statement-breakpoint
CREATE INDEX "audit_events_created_index" ON "app"."audit_events" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "audit_events_actor_time_index" ON "app"."audit_events" USING btree ("actor_user_id","created_at");--> statement-breakpoint
CREATE INDEX "audit_events_action_time_index" ON "app"."audit_events" USING btree ("action","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "sync_changes_event_unique" ON "app"."sync_changes" USING btree ("event_id");--> statement-breakpoint
CREATE INDEX "sync_changes_user_time_index" ON "app"."sync_changes" USING btree ("user_id","occurred_at");--> statement-breakpoint

INSERT INTO "app"."regions" ("id", "country_code", "name_en", "name_zh")
VALUES
	('london', 'GB', 'London', '伦敦'),
	('melbourne', 'AU', 'Melbourne', '墨尔本'),
	('newyork', 'US', 'New York', '纽约'),
	('capetown', 'ZA', 'Cape Town', '开普敦'),
	('singapore', 'SG', 'Singapore', '新加坡'),
	('dublin', 'IE', 'Dublin', '都柏林'),
	('edinburgh', 'GB', 'Edinburgh', '爱丁堡'),
	('vancouver', 'CA', 'Vancouver', '温哥华'),
	('auckland', 'NZ', 'Auckland', '奥克兰'),
	('nairobi', 'KE', 'Nairobi', '内罗毕'),
	('reykjavik', 'IS', 'Reykjavík', '雷克雅未克'),
	('lisbon', 'PT', 'Lisbon', '里斯本'),
	('tokyo', 'JP', 'Tokyo', '东京');--> statement-breakpoint

INSERT INTO "app"."billing_plans" (
	"id",
	"tier",
	"rank",
	"display_name",
	"feature_flags"
)
VALUES
	(
		'free',
		'free',
		0,
		'Free',
		'{"aiDailyRequests":30,"aiAdvancedFeatures":false,"friendSlotLimit":3,"priorityAi":false}'::jsonb
	),
	(
		'plus',
		'plus',
		10,
		'Plus',
		'{"aiDailyRequests":300,"aiAdvancedFeatures":true,"friendSlotLimit":10,"priorityAi":false}'::jsonb
	),
	(
		'pro',
		'pro',
		20,
		'Pro',
		'{"aiDailyRequests":1500,"aiAdvancedFeatures":true,"friendSlotLimit":30,"priorityAi":true}'::jsonb
	);--> statement-breakpoint

INSERT INTO "app"."store_products" (
	"provider",
	"product_id",
	"plan_id"
)
VALUES
	('apple', 'com.tiantian.lingotrip.plus.monthly', 'plus'),
	('apple', 'com.tiantian.lingotrip.plus.yearly', 'plus'),
	('apple', 'com.tiantian.lingotrip.pro.monthly', 'pro'),
	('apple', 'com.tiantian.lingotrip.pro.yearly', 'pro');--> statement-breakpoint

INSERT INTO "app"."ai_routes" (
	"task",
	"provider",
	"model",
	"max_messages",
	"max_input_characters",
	"max_output_tokens",
	"temperature",
	"allow_json_response",
	"timeout_ms",
	"provider_options"
)
VALUES
	(
		'conversation',
		'deepseek',
		'deepseek-v4-flash',
		48,
		60000,
		2048,
		0.8,
		false,
		60000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'quiz',
		'deepseek',
		'deepseek-v4-flash',
		16,
		24000,
		1600,
		0.4,
		true,
		45000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'character_generation',
		'deepseek',
		'deepseek-v4-flash',
		12,
		24000,
		2400,
		0.7,
		true,
		60000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'memory_summary',
		'deepseek',
		'deepseek-v4-flash',
		80,
		80000,
		1600,
		0.2,
		true,
		60000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'translation',
		'deepseek',
		'deepseek-v4-flash',
		12,
		16000,
		1200,
		0.2,
		false,
		30000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'speech_feedback',
		'deepseek',
		'deepseek-v4-flash',
		20,
		32000,
		1600,
		0.3,
		true,
		45000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'coach_review',
		'deepseek',
		'deepseek-v4-flash',
		12,
		16000,
		1200,
		0.2,
		true,
		45000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	),
	(
		'dictionary_explain',
		'deepseek',
		'deepseek-v4-flash',
		8,
		8000,
		800,
		0.2,
		false,
		30000,
		'{"thinking":{"type":"disabled"}}'::jsonb
	);--> statement-breakpoint

INSERT INTO "app"."ai_route_revisions" (
	"id",
	"task",
	"config_version",
	"command_id",
	"request_hash",
	"operator_key_id",
	"change_reason",
	"previous_config",
	"new_config"
)
SELECT
	md5('ai-route-baseline-id:' || "task")::uuid,
	"task",
	"config_version",
	md5('ai-route-baseline-command:' || "task")::uuid,
	md5('ai-route-baseline-request:' || "task") ||
		md5('ai-route-baseline-request-2:' || "task"),
	'system:baseline',
	'Initial route configuration',
	jsonb_build_object(
		'allowJsonResponse', "allow_json_response",
		'enabled', "enabled",
		'maxInputCharacters', "max_input_characters",
		'maxMessages', "max_messages",
		'maxOutputTokens', "max_output_tokens",
		'model', "model",
		'provider', "provider",
		'providerOptions', "provider_options",
		'temperature', "temperature",
		'timeoutMs', "timeout_ms"
	),
	jsonb_build_object(
		'allowJsonResponse', "allow_json_response",
		'enabled', "enabled",
		'maxInputCharacters', "max_input_characters",
		'maxMessages', "max_messages",
		'maxOutputTokens', "max_output_tokens",
		'model', "model",
		'provider', "provider",
		'providerOptions', "provider_options",
		'temperature', "temperature",
		'timeoutMs', "timeout_ms"
	)
FROM "app"."ai_routes";
