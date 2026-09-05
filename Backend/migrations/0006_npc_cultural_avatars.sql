CREATE TABLE "app"."user_npc_avatars" (
	"user_id" uuid NOT NULL,
	"npc_id" uuid NOT NULL,
	"avatar_id" uuid NOT NULL,
	"family_id" uuid NOT NULL,
	"reason" jsonb NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "user_npc_avatars_primary" PRIMARY KEY("user_id","npc_id")
);
--> statement-breakpoint
DROP INDEX "app"."public_npcs_avatar_id_unique";--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "family_id" uuid;
--> statement-breakpoint
UPDATE "app"."npc_avatars" SET "family_id" = "id";
--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ALTER COLUMN "family_id" SET NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "sha256" text;--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "metadata" jsonb;--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "reserved" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "withdrawn" boolean DEFAULT false NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."user_npc_avatars" ADD CONSTRAINT "user_npc_avatars_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."user_npc_avatars" ADD CONSTRAINT "user_npc_avatars_npc_id_public_npcs_id_fk" FOREIGN KEY ("npc_id") REFERENCES "app"."public_npcs"("id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "npc_avatars_id_family_unique" ON "app"."npc_avatars" USING btree ("id","family_id");--> statement-breakpoint
ALTER TABLE "app"."user_npc_avatars" ADD CONSTRAINT "user_npc_avatars_asset_fk" FOREIGN KEY ("avatar_id","family_id") REFERENCES "app"."npc_avatars"("id","family_id") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "user_npc_avatars_family_unique" ON "app"."user_npc_avatars" USING btree ("user_id","family_id");--> statement-breakpoint
CREATE UNIQUE INDEX "npc_avatars_sha256_unique" ON "app"."npc_avatars" USING btree ("sha256");--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD CONSTRAINT "npc_avatars_sha256_format" CHECK ("app"."npc_avatars"."sha256" is null or "app"."npc_avatars"."sha256" ~ '^[a-f0-9]{64}$');
--> statement-breakpoint
-- Preserve every known encounter, including removed relationships and the original creator.
INSERT INTO app.user_npc_avatars (user_id, npc_id, avatar_id, family_id, reason)
SELECT seen.user_id, npc.id, npc.avatar_id, asset.family_id, '{"version":0,"source":"legacy"}'::jsonb
FROM (
  SELECT user_id, npc_id FROM app.user_npc_relationships
  UNION
  SELECT created_by_user_id, id FROM app.public_npcs WHERE created_by_user_id IS NOT NULL
) seen
JOIN app.public_npcs npc ON npc.id = seen.npc_id
JOIN app.npc_avatars asset ON asset.id = npc.avatar_id
ON CONFLICT DO NOTHING;
