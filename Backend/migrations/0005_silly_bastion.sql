CREATE TYPE "app"."billing_environment" AS ENUM('sandbox', 'production', 'test');--> statement-breakpoint
CREATE TYPE "app"."billing_provider" AS ENUM('apple', 'google_play', 'stripe', 'manual');--> statement-breakpoint
CREATE TYPE "app"."entitlement_status" AS ENUM('active', 'grace', 'billing_retry', 'expired', 'revoked');--> statement-breakpoint
CREATE TYPE "app"."subscription_tier" AS ENUM('free', 'plus', 'pro');--> statement-breakpoint
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
	"user_id" uuid NOT NULL,
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
	"status" "app"."entitlement_status" NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."billing_provider_events" ADD CONSTRAINT "billing_provider_events_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ADD CONSTRAINT "billing_transactions_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ADD CONSTRAINT "billing_transactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."entitlement_grants" ADD CONSTRAINT "entitlement_grants_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."entitlement_grants" ADD CONSTRAINT "entitlement_grants_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."store_products" ADD CONSTRAINT "store_products_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_plan_id_billing_plans_id_fk" FOREIGN KEY ("plan_id") REFERENCES "app"."billing_plans"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
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
CREATE INDEX "subscriptions_user_status_index" ON "app"."subscriptions" USING btree ("user_id","status");
--> statement-breakpoint
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
	)
ON CONFLICT ("id") DO UPDATE
SET "tier" = EXCLUDED."tier",
	"rank" = EXCLUDED."rank",
	"display_name" = EXCLUDED."display_name",
	"feature_flags" = EXCLUDED."feature_flags",
	"updated_at" = now();
--> statement-breakpoint
INSERT INTO "app"."store_products" (
	"provider",
	"product_id",
	"plan_id"
)
VALUES
	('apple', 'com.tiantian.lingotrip.plus.monthly', 'plus'),
	('apple', 'com.tiantian.lingotrip.plus.yearly', 'plus'),
	('apple', 'com.tiantian.lingotrip.pro.monthly', 'pro'),
	('apple', 'com.tiantian.lingotrip.pro.yearly', 'pro')
ON CONFLICT ("provider", "product_id") DO UPDATE
SET "plan_id" = EXCLUDED."plan_id",
	"is_active" = true,
	"updated_at" = now();
