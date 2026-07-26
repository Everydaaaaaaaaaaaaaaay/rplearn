ALTER TABLE "app"."subscriptions" ADD COLUMN "reconcile_after" timestamp with time zone DEFAULT now() NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD COLUMN "reconciliation_attempts" integer DEFAULT 0 NOT NULL;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD COLUMN "reconciliation_error" text;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD COLUMN "reconciliation_started_at" timestamp with time zone;--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD COLUMN "last_reconciled_at" timestamp with time zone;--> statement-breakpoint
CREATE INDEX "subscriptions_reconcile_due_index" ON "app"."subscriptions" USING btree ("reconcile_after","updated_at") WHERE "app"."subscriptions"."provider" = 'apple'
          and "app"."subscriptions"."user_id" is not null
          and "app"."subscriptions"."environment" in ('production', 'sandbox');--> statement-breakpoint
ALTER TABLE "app"."subscriptions" ADD CONSTRAINT "subscriptions_reconciliation_attempts_nonnegative" CHECK ("app"."subscriptions"."reconciliation_attempts" >= 0);