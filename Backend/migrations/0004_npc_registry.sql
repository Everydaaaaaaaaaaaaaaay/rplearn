CREATE TYPE "app"."npc_relationship_status" AS ENUM('candidate', 'friend', 'removed');--> statement-breakpoint
CREATE TABLE "app"."npc_avatars" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"image_url" text NOT NULL,
	"tags" jsonb DEFAULT '[]'::jsonb NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "npc_avatars_https_url" CHECK ("app"."npc_avatars"."image_url" ~ '^https://[^[:space:]]+$' and octet_length("app"."npc_avatars"."image_url") <= 2048),
	CONSTRAINT "npc_avatars_tags_size" CHECK (octet_length("app"."npc_avatars"."tags"::text) <= 4096)
);
--> statement-breakpoint
CREATE TABLE "app"."public_npcs" (
	"avatar_id" uuid,
	"card" jsonb NOT NULL,
	"card_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"created_by_user_id" uuid,
	"id" uuid PRIMARY KEY NOT NULL,
	"traveler_id" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "public_npcs_traveler_id_format" CHECK ("app"."public_npcs"."traveler_id" ~ '^[0-9]{11}$'),
	CONSTRAINT "public_npcs_card_hash_format" CHECK ("app"."public_npcs"."card_hash" ~ '^[0-9a-f]{64}$'),
	CONSTRAINT "public_npcs_card_size" CHECK (octet_length("app"."public_npcs"."card"::text) <= 32768)
);
--> statement-breakpoint
CREATE TABLE "app"."user_npc_relationships" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"local_character_id" uuid NOT NULL,
	"npc_id" uuid NOT NULL,
	"status" "app"."npc_relationship_status" DEFAULT 'candidate' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "user_npc_relationships_primary" PRIMARY KEY("user_id","npc_id")
);
--> statement-breakpoint
ALTER TABLE "app"."public_npcs" ADD CONSTRAINT "public_npcs_avatar_id_npc_avatars_id_fk" FOREIGN KEY ("avatar_id") REFERENCES "app"."npc_avatars"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."public_npcs" ADD CONSTRAINT "public_npcs_created_by_user_id_users_id_fk" FOREIGN KEY ("created_by_user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_npc_relationships" ADD CONSTRAINT "user_npc_relationships_npc_id_public_npcs_id_fk" FOREIGN KEY ("npc_id") REFERENCES "app"."public_npcs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_npc_relationships" ADD CONSTRAINT "user_npc_relationships_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "npc_avatars_image_url_unique" ON "app"."npc_avatars" USING btree ("image_url");--> statement-breakpoint
CREATE INDEX "npc_avatars_enabled_index" ON "app"."npc_avatars" USING btree ("enabled","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "public_npcs_traveler_id_unique" ON "app"."public_npcs" USING btree ("traveler_id");--> statement-breakpoint
CREATE UNIQUE INDEX "public_npcs_avatar_id_unique" ON "app"."public_npcs" USING btree ("avatar_id") WHERE "app"."public_npcs"."avatar_id" is not null;--> statement-breakpoint
CREATE INDEX "public_npcs_creator_index" ON "app"."public_npcs" USING btree ("created_by_user_id","created_at");--> statement-breakpoint
CREATE UNIQUE INDEX "user_npc_relationships_local_character_unique" ON "app"."user_npc_relationships" USING btree ("user_id","local_character_id");--> statement-breakpoint
CREATE INDEX "user_npc_relationships_status_index" ON "app"."user_npc_relationships" USING btree ("user_id","status");
