CREATE TYPE "app"."difficulty_level" AS ENUM('primary1', 'primary2', 'primary3', 'primary4', 'primary5', 'primary6', 'junior1', 'junior2', 'junior3', 'senior1', 'senior2', 'senior3', 'undergraduate', 'postgraduate', 'advanced');--> statement-breakpoint
CREATE TYPE "app"."inventory_status" AS ENUM('available', 'consumed', 'revoked');--> statement-breakpoint
CREATE TYPE "app"."ticket_source" AS ENUM('story', 'quest', 'purchase', 'subscription', 'support', 'debug');--> statement-breakpoint
CREATE TYPE "app"."ticket_type" AS ENUM('universal', 'country');--> statement-breakpoint
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
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid PRIMARY KEY NOT NULL,
	"version" integer DEFAULT 1 NOT NULL,
	CONSTRAINT "user_profiles_coins_nonnegative" CHECK ("app"."user_profiles"."coins" >= 0),
	CONSTRAINT "user_profiles_experience_nonnegative" CHECK ("app"."user_profiles"."experience_points" >= 0),
	CONSTRAINT "user_profiles_level_positive" CHECK ("app"."user_profiles"."game_level" >= 1),
	CONSTRAINT "user_profiles_version_positive" CHECK ("app"."user_profiles"."version" >= 1)
);
--> statement-breakpoint
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
ALTER TABLE "app"."user_profiles" ADD CONSTRAINT "user_profiles_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "coin_ledger_user_created_index" ON "app"."coin_ledger" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "coin_ledger_reference_unique" ON "app"."coin_ledger" USING btree ("user_id","reference_type","reference_id") WHERE "app"."coin_ledger"."reference_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "command_receipts_user_command_unique" ON "app"."command_receipts" USING btree ("user_id","command_id");--> statement-breakpoint
CREATE INDEX "command_receipts_created_index" ON "app"."command_receipts" USING btree ("created_at");--> statement-breakpoint
CREATE INDEX "inventory_user_status_index" ON "app"."inventory_items" USING btree ("user_id","status");--> statement-breakpoint
CREATE UNIQUE INDEX "inventory_source_reference_unique" ON "app"."inventory_items" USING btree ("user_id","source","source_reference_id") WHERE "app"."inventory_items"."source_reference_id" is not null;--> statement-breakpoint
CREATE UNIQUE INDEX "region_unlocks_user_region_unique" ON "app"."region_unlocks" USING btree ("user_id","region_id");--> statement-breakpoint
CREATE INDEX "region_unlocks_user_time_index" ON "app"."region_unlocks" USING btree ("user_id","unlocked_at");--> statement-breakpoint
CREATE INDEX "travel_records_user_time_index" ON "app"."travel_records" USING btree ("user_id","traveled_at");
--> statement-breakpoint
INSERT INTO "app"."regions" ("id", "country_code", "name_en", "name_zh")
VALUES
	('london', 'GB', 'London', '伦敦'),
	('melbourne', 'AU', 'Melbourne', '墨尔本'),
	('newyork', 'US', 'New York', '纽约')
ON CONFLICT ("id") DO UPDATE
SET "country_code" = EXCLUDED."country_code",
	"name_en" = EXCLUDED."name_en",
	"name_zh" = EXCLUDED."name_zh";
