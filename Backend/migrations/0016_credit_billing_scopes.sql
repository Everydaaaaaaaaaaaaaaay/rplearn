ALTER TABLE "app"."credit_operations" ADD COLUMN "billing_scope" text DEFAULT 'user' NOT NULL;
--> statement-breakpoint
UPDATE "app"."credit_operations"
SET "billing_scope" = 'service'
WHERE "task" IN ('coach_review', 'memory_summary', 'proactive_message', 'quiz', 'speech_feedback');
--> statement-breakpoint
ALTER TABLE "app"."credit_operations" ADD CONSTRAINT "credit_operations_billing_scope_check" CHECK ("app"."credit_operations"."billing_scope" in ('user','service'));
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
VALUES (
	'proactive_message',
	'deepseek',
	'deepseek-v4-flash',
	12,
	16000,
	128,
	0.8,
	false,
	30000,
	'{"thinking":{"type":"disabled"}}'::jsonb
);
--> statement-breakpoint
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
VALUES (
	md5('ai-route-baseline-id:proactive_message')::uuid,
	'proactive_message',
	1,
	md5('ai-route-baseline-command:proactive_message')::uuid,
	md5('ai-route-baseline-request:proactive_message') ||
		md5('ai-route-baseline-request-2:proactive_message'),
	'system:baseline',
	'Separate product-initiated messages from user-billed conversations',
	'{}'::jsonb,
	'{
		"allowJsonResponse": false,
		"enabled": true,
		"maxInputCharacters": 16000,
		"maxMessages": 12,
		"maxOutputTokens": 128,
		"model": "deepseek-v4-flash",
		"provider": "deepseek",
		"providerOptions": {"thinking": {"type": "disabled"}},
		"temperature": 0.8,
		"timeoutMs": 30000
	}'::jsonb
);
