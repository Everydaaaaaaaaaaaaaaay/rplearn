CREATE TYPE "app"."ai_provider" AS ENUM('deepseek', 'openai', 'anthropic', 'google');--> statement-breakpoint
CREATE TYPE "app"."ai_request_status" AS ENUM('started', 'succeeded', 'failed', 'cancelled');--> statement-breakpoint
CREATE TABLE "app"."ai_daily_usage" (
	"input_tokens" integer DEFAULT 0 NOT NULL,
	"output_tokens" integer DEFAULT 0 NOT NULL,
	"quota_limit" integer NOT NULL,
	"request_count" integer DEFAULT 0 NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	"usage_date" date NOT NULL,
	"user_id" uuid NOT NULL,
	CONSTRAINT "ai_daily_usage_user_date_pk" PRIMARY KEY("user_id","usage_date"),
	CONSTRAINT "ai_daily_usage_request_nonnegative" CHECK ("app"."ai_daily_usage"."request_count" >= 0),
	CONSTRAINT "ai_daily_usage_input_nonnegative" CHECK ("app"."ai_daily_usage"."input_tokens" >= 0),
	CONSTRAINT "ai_daily_usage_output_nonnegative" CHECK ("app"."ai_daily_usage"."output_tokens" >= 0),
	CONSTRAINT "ai_daily_usage_quota_positive" CHECK ("app"."ai_daily_usage"."quota_limit" >= 1)
);
--> statement-breakpoint
CREATE TABLE "app"."ai_requests" (
	"completed_at" timestamp with time zone,
	"config_version" integer NOT NULL,
	"error_code" text,
	"id" uuid PRIMARY KEY NOT NULL,
	"input_characters" integer NOT NULL,
	"input_tokens" integer,
	"latency_ms" integer,
	"model" text NOT NULL,
	"output_tokens" integer,
	"provider" "app"."ai_provider" NOT NULL,
	"requested_at" timestamp with time zone DEFAULT now() NOT NULL,
	"status" "app"."ai_request_status" DEFAULT 'started' NOT NULL,
	"task" text NOT NULL,
	"upstream_request_id" text,
	"user_id" uuid NOT NULL,
	CONSTRAINT "ai_requests_input_characters_nonnegative" CHECK ("app"."ai_requests"."input_characters" >= 0),
	CONSTRAINT "ai_requests_input_tokens_nonnegative" CHECK ("app"."ai_requests"."input_tokens" is null or "app"."ai_requests"."input_tokens" >= 0),
	CONSTRAINT "ai_requests_output_tokens_nonnegative" CHECK ("app"."ai_requests"."output_tokens" is null or "app"."ai_requests"."output_tokens" >= 0),
	CONSTRAINT "ai_requests_latency_nonnegative" CHECK ("app"."ai_requests"."latency_ms" is null or "app"."ai_requests"."latency_ms" >= 0)
);
--> statement-breakpoint
CREATE TABLE "app"."ai_routes" (
	"allow_json_response" boolean DEFAULT false NOT NULL,
	"config_version" integer DEFAULT 1 NOT NULL,
	"enabled" boolean DEFAULT true NOT NULL,
	"max_input_characters" integer NOT NULL,
	"max_messages" integer NOT NULL,
	"max_output_tokens" integer NOT NULL,
	"model" text NOT NULL,
	"provider" "app"."ai_provider" NOT NULL,
	"provider_options" jsonb DEFAULT '{}'::jsonb NOT NULL,
	"task" text PRIMARY KEY NOT NULL,
	"temperature" real,
	"timeout_ms" integer NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "ai_routes_config_version_positive" CHECK ("app"."ai_routes"."config_version" >= 1),
	CONSTRAINT "ai_routes_max_messages_positive" CHECK ("app"."ai_routes"."max_messages" >= 1),
	CONSTRAINT "ai_routes_max_input_characters_positive" CHECK ("app"."ai_routes"."max_input_characters" >= 1),
	CONSTRAINT "ai_routes_max_output_tokens_positive" CHECK ("app"."ai_routes"."max_output_tokens" >= 1),
	CONSTRAINT "ai_routes_timeout_positive" CHECK ("app"."ai_routes"."timeout_ms" >= 1000),
	CONSTRAINT "ai_routes_temperature_range" CHECK ("app"."ai_routes"."temperature" is null or
        ("app"."ai_routes"."temperature" >= 0 and "app"."ai_routes"."temperature" <= 2))
);
--> statement-breakpoint
ALTER TABLE "app"."ai_daily_usage" ADD CONSTRAINT "ai_daily_usage_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "app"."ai_requests" ADD CONSTRAINT "ai_requests_user_id_users_id_fk" FOREIGN KEY ("user_id") REFERENCES "app"."users"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "ai_requests_user_time_index" ON "app"."ai_requests" USING btree ("user_id","requested_at");--> statement-breakpoint
CREATE INDEX "ai_requests_status_time_index" ON "app"."ai_requests" USING btree ("status","requested_at");
--> statement-breakpoint
INSERT INTO "app"."ai_routes" (
	"task",
	"provider",
	"model",
	"max_messages",
	"max_input_characters",
	"max_output_tokens",
	"temperature",
	"allow_json_response",
	"timeout_ms",
	"provider_options"
)
VALUES
	(
		'conversation',
		'deepseek',
		'deepseek-v4-flash',
		48,
		60000,
		2048,
		0.8,
		false,
		60000,
		'{}'::jsonb
	),
	(
		'quiz',
		'deepseek',
		'deepseek-v4-flash',
		16,
		24000,
		1600,
		0.4,
		true,
		45000,
		'{}'::jsonb
	),
	(
		'character_generation',
		'deepseek',
		'deepseek-v4-flash',
		12,
		24000,
		2400,
		0.7,
		true,
		60000,
		'{}'::jsonb
	),
	(
		'memory_summary',
		'deepseek',
		'deepseek-v4-flash',
		80,
		80000,
		1600,
		0.2,
		true,
		60000,
		'{}'::jsonb
	),
	(
		'translation',
		'deepseek',
		'deepseek-v4-flash',
		12,
		16000,
		1200,
		0.2,
		false,
		30000,
		'{}'::jsonb
	),
	(
		'speech_feedback',
		'deepseek',
		'deepseek-v4-flash',
		20,
		32000,
		1600,
		0.3,
		true,
		45000,
		'{}'::jsonb
	)
ON CONFLICT ("task") DO UPDATE
SET "provider" = EXCLUDED."provider",
	"model" = EXCLUDED."model",
	"max_messages" = EXCLUDED."max_messages",
	"max_input_characters" = EXCLUDED."max_input_characters",
	"max_output_tokens" = EXCLUDED."max_output_tokens",
	"temperature" = EXCLUDED."temperature",
	"allow_json_response" = EXCLUDED."allow_json_response",
	"timeout_ms" = EXCLUDED."timeout_ms",
	"provider_options" = EXCLUDED."provider_options",
	"enabled" = true,
	"config_version" = "app"."ai_routes"."config_version" + 1,
	"updated_at" = now();
