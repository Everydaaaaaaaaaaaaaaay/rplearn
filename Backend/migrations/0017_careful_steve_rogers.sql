CREATE TABLE "app"."ai_guest_principals" (
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"device_reference" char(64) NOT NULL,
	"last_seen_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid PRIMARY KEY NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."ai_guest_principals" ADD CONSTRAINT "ai_guest_principals_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "ai_guest_principals_device_unique" ON "app"."ai_guest_principals" USING btree ("device_reference");