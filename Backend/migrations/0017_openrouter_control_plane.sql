ALTER TYPE "app"."ai_provider" ADD VALUE 'openrouter' BEFORE 'openai';--> statement-breakpoint
CREATE TABLE "app"."ai_model_catalog" (
	"architecture" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"available" boolean DEFAULT true NOT NULL,
	"cached_input_price_usd" numeric(30, 18),
	"completion_price_usd" numeric(30, 18) NOT NULL,
	"context_length" integer,
	"display_name" text NOT NULL,
	"model" text NOT NULL,
	"prompt_price_usd" numeric(30, 18) NOT NULL,
	"provider" "app"."ai_provider" NOT NULL,
	"refreshed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"supported_parameters" jsonb DEFAULT '[]'::jsonb NOT NULL,
	CONSTRAINT "ai_model_catalog_provider_model_pk" PRIMARY KEY("provider","model"),
	CONSTRAINT "ai_model_catalog_context_positive" CHECK ("app"."ai_model_catalog"."context_length" is null or "app"."ai_model_catalog"."context_length" > 0),
	CONSTRAINT "ai_model_catalog_prices_nonnegative" CHECK ("app"."ai_model_catalog"."prompt_price_usd" >= 0 and "app"."ai_model_catalog"."completion_price_usd" >= 0 and ("app"."ai_model_catalog"."cached_input_price_usd" is null or "app"."ai_model_catalog"."cached_input_price_usd" >= 0))
);
--> statement-breakpoint
ALTER TABLE "app"."ai_requests" ADD COLUMN "provider_cost_usd" numeric(24, 12);--> statement-breakpoint
CREATE INDEX "ai_model_catalog_provider_name_index" ON "app"."ai_model_catalog" USING btree ("provider","display_name");--> statement-breakpoint
ALTER TABLE "app"."ai_requests" ADD CONSTRAINT "ai_requests_provider_cost_nonnegative" CHECK ("app"."ai_requests"."provider_cost_usd" is null or "app"."ai_requests"."provider_cost_usd" >= 0);
