CREATE TABLE "app"."npc_pending_avatars" (
	"npc_id" uuid PRIMARY KEY NOT NULL,
	"user_id" uuid NOT NULL,
	"input" jsonb NOT NULL,
	"card_hash" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"next_attempt_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "npc_pending_avatars_input_size" CHECK (octet_length("app"."npc_pending_avatars"."input"::text) <= 36864),
	CONSTRAINT "npc_pending_avatars_hash_format" CHECK ("app"."npc_pending_avatars"."card_hash" ~ '^[0-9a-f]{64}$')
);
--> statement-breakpoint
ALTER TABLE "app"."npc_pending_avatars" ADD CONSTRAINT "npc_pending_avatars_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "npc_pending_avatars_due_index" ON "app"."npc_pending_avatars" USING btree ("next_attempt_at","npc_id");--> statement-breakpoint
CREATE INDEX "npc_pending_avatars_user_index" ON "app"."npc_pending_avatars" USING btree ("user_id");