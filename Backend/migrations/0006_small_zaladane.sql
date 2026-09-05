CREATE TABLE "app"."npc_avatar_match_events" (
	"npc_id" uuid NOT NULL,
	"user_id" uuid NOT NULL,
	"requirements" jsonb NOT NULL,
	"reason" text NOT NULL,
	"eligible_count" integer NOT NULL,
	"unseen_count" integer NOT NULL,
	"selected_avatar_id" uuid,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "npc_avatar_match_events_user_id_npc_id_pk" PRIMARY KEY("user_id","npc_id")
);
--> statement-breakpoint
DROP INDEX "app"."public_npcs_avatar_id_unique";--> statement-breakpoint
ALTER TABLE "app"."npc_avatars" ADD COLUMN "profile" jsonb;--> statement-breakpoint
ALTER TABLE "app"."npc_avatar_match_events" ADD CONSTRAINT "npc_avatar_match_events_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."npc_avatar_match_events" ADD CONSTRAINT "npc_avatar_match_events_selected_avatar_id_npc_avatars_id_fk" FOREIGN KEY ("selected_avatar_id") REFERENCES "app"."npc_avatars"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "public_npcs_avatar_id_index" ON "app"."public_npcs" USING btree ("avatar_id");