CREATE TYPE "app"."job_status" AS ENUM('pending', 'running', 'succeeded', 'dead', 'cancelled');--> statement-breakpoint
CREATE TABLE "app"."jobs" (
	"attempts" integer DEFAULT 0 NOT NULL,
	"available_at" timestamp with time zone DEFAULT now() NOT NULL,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"key_version" text NOT NULL,
	"last_error" text,
	"lease_expires_at" timestamp with time zone,
	"locked_by" text,
	"max_attempts" integer DEFAULT 8 NOT NULL,
	"nonce" "bytea" NOT NULL,
	"payload_ciphertext" "bytea" NOT NULL,
	"status" "app"."job_status" DEFAULT 'pending' NOT NULL,
	"tag" "bytea" NOT NULL,
	"type" text NOT NULL,
	"unique_key" text,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	CONSTRAINT "jobs_attempts_nonnegative" CHECK ("app"."jobs"."attempts" >= 0),
	CONSTRAINT "jobs_max_attempts_positive" CHECK ("app"."jobs"."max_attempts" > 0)
);
--> statement-breakpoint
ALTER TABLE "app"."jobs" ADD CONSTRAINT "jobs_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "jobs_unique_key_unique" ON "app"."jobs" USING btree ("unique_key") WHERE "app"."jobs"."unique_key" is not null;--> statement-breakpoint
CREATE INDEX "jobs_pending_available_index" ON "app"."jobs" USING btree ("available_at","created_at") WHERE "app"."jobs"."status" = 'pending';--> statement-breakpoint
CREATE INDEX "jobs_running_lease_index" ON "app"."jobs" USING btree ("lease_expires_at") WHERE "app"."jobs"."status" = 'running';--> statement-breakpoint
CREATE INDEX "jobs_user_created_index" ON "app"."jobs" USING btree ("user_id","created_at");--> statement-breakpoint
CREATE INDEX "jobs_completed_index" ON "app"."jobs" USING btree ("completed_at") WHERE "app"."jobs"."status" in ('succeeded', 'cancelled');