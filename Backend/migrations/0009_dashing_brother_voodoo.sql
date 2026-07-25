CREATE TYPE "app"."account_deletion_status" AS ENUM('scheduled', 'processing', 'cancelled', 'completed');--> statement-breakpoint
CREATE TABLE "app"."account_deletion_requests" (
	"cancellation_token_hash" char(64),
	"cancelled_at" timestamp with time zone,
	"completed_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"purge_at" timestamp with time zone NOT NULL,
	"status" "app"."account_deletion_status" DEFAULT 'scheduled' NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"user_id" uuid,
	"user_reference_hash" char(64) NOT NULL
);
--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" DROP CONSTRAINT "billing_transactions_user_id_users_id_fk";
--> statement-breakpoint
ALTER TABLE "app"."subscriptions" DROP CONSTRAINT "subscriptions_user_id_users_id_fk";
--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ALTER COLUMN "user_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ALTER COLUMN "user_id" DROP NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."identity_provider_credentials" ADD COLUMN "provider_client_id" text;--> statement-breakpoint
ALTER TABLE "app"."account_deletion_requests" ADD CONSTRAINT "account_deletion_requests_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "account_deletions_active_user_unique" ON "app"."account_deletion_requests" USING btree ("user_id") WHERE "app"."account_deletion_requests"."status" in ('scheduled', 'processing');--> statement-breakpoint
CREATE UNIQUE INDEX "account_deletions_cancel_token_unique" ON "app"."account_deletion_requests" USING btree ("cancellation_token_hash") WHERE "app"."account_deletion_requests"."cancellation_token_hash" is not null;--> statement-breakpoint
CREATE INDEX "account_deletions_due_index" ON "app"."account_deletion_requests" USING btree ("purge_at") WHERE "app"."account_deletion_requests"."status" in ('scheduled', 'processing');--> statement-breakpoint
CREATE INDEX "account_deletions_reference_index" ON "app"."account_deletion_requests" USING btree ("user_reference_hash");--> statement-breakpoint
ALTER TABLE "app"."billing_transactions" ADD CONSTRAINT "billing_transactions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;