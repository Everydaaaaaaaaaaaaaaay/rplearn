CREATE TABLE "app"."ai_route_revisions" (
	"changed_at" timestamp with time zone DEFAULT now() NOT NULL,
	"change_reason" text NOT NULL,
	"command_id" uuid NOT NULL,
	"config_version" integer NOT NULL,
	"id" uuid PRIMARY KEY NOT NULL,
	"new_config" jsonb NOT NULL,
	"operator_key_id" text NOT NULL,
	"previous_config" jsonb NOT NULL,
	"request_hash" text NOT NULL,
	"task" text NOT NULL,
	CONSTRAINT "ai_route_revisions_config_version_positive" CHECK ("app"."ai_route_revisions"."config_version" >= 1)
);
--> statement-breakpoint
ALTER TABLE "app"."ai_route_revisions" ADD CONSTRAINT "ai_route_revisions_task_ai_routes_task_fk" FOREIGN KEY ("task") REFERENCES "app"."ai_routes"("task") ON DELETE restrict ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "ai_route_revisions_command_unique" ON "app"."ai_route_revisions" USING btree ("command_id");--> statement-breakpoint
CREATE UNIQUE INDEX "ai_route_revisions_task_version_unique" ON "app"."ai_route_revisions" USING btree ("task","config_version");--> statement-breakpoint
CREATE INDEX "ai_route_revisions_task_time_index" ON "app"."ai_route_revisions" USING btree ("task","changed_at");--> statement-breakpoint
INSERT INTO "app"."ai_route_revisions" (
	"id",
	"task",
	"config_version",
	"command_id",
	"request_hash",
	"operator_key_id",
	"change_reason",
	"previous_config",
	"new_config"
)
SELECT
	md5('ai-route-baseline-id:' || "task")::uuid,
	"task",
	"config_version",
	md5('ai-route-baseline-command:' || "task")::uuid,
	md5('ai-route-baseline-request:' || "task") ||
		md5('ai-route-baseline-request-2:' || "task"),
	'system:migration',
	'Baseline captured before managed configuration changes',
	jsonb_build_object(
		'allowJsonResponse', "allow_json_response",
		'enabled', "enabled",
		'maxInputCharacters', "max_input_characters",
		'maxMessages', "max_messages",
		'maxOutputTokens', "max_output_tokens",
		'model', "model",
		'provider', "provider",
		'providerOptions', "provider_options",
		'temperature', "temperature",
		'timeoutMs', "timeout_ms"
	),
	jsonb_build_object(
		'allowJsonResponse', "allow_json_response",
		'enabled', "enabled",
		'maxInputCharacters', "max_input_characters",
		'maxMessages', "max_messages",
		'maxOutputTokens', "max_output_tokens",
		'model', "model",
		'provider', "provider",
		'providerOptions', "provider_options",
		'temperature', "temperature",
		'timeoutMs', "timeout_ms"
	)
FROM "app"."ai_routes";
