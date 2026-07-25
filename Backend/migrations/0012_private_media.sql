CREATE TYPE "app"."media_status" AS ENUM('pending', 'ready', 'deleted');--> statement-breakpoint
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
ALTER TABLE "app"."media_assets" ADD CONSTRAINT "media_assets_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "media_assets_user_status_index" ON "app"."media_assets" USING btree ("user_id","status","created_at");--> statement-breakpoint
CREATE INDEX "media_assets_pending_expiry_index" ON "app"."media_assets" USING btree ("pending_expires_at") WHERE "app"."media_assets"."status" = 'pending';--> statement-breakpoint
CREATE INDEX "media_assets_purged_retention_index" ON "app"."media_assets" USING btree ("purged_at") WHERE "app"."media_assets"."status" = 'deleted' and "app"."media_assets"."purged_at" is not null;
