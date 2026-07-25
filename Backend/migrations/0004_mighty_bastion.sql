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
ALTER TABLE "app"."sync_changes" ADD CONSTRAINT "sync_changes_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."sync_heads" ADD CONSTRAINT "sync_heads_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "sync_changes_event_unique" ON "app"."sync_changes" USING btree ("event_id");--> statement-breakpoint
CREATE INDEX "sync_changes_user_time_index" ON "app"."sync_changes" USING btree ("user_id","occurred_at");