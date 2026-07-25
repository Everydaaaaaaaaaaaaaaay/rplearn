CREATE TYPE "app"."content_resource_type" AS ENUM('character', 'conversation', 'favorite', 'memory', 'message', 'quiz_record', 'story_progress');--> statement-breakpoint
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
ALTER TABLE "app"."content_records" ADD CONSTRAINT "content_records_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "content_records_user_parent_index" ON "app"."content_records" USING btree ("user_id","parent_id","resource_type");--> statement-breakpoint
CREATE INDEX "content_records_user_updated_index" ON "app"."content_records" USING btree ("user_id","updated_at");