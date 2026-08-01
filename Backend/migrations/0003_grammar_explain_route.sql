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
	'grammar_explain',
	'deepseek',
	'deepseek-v4-flash',
	4,
	12000,
	1200,
	0.2,
	true,
	30000,
	'{"thinking":{"type":"disabled"}}'::jsonb
);--> statement-breakpoint

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
	md5('ai-route-baseline-id:grammar_explain')::uuid,
	'grammar_explain',
	1,
	md5('ai-route-baseline-command:grammar_explain')::uuid,
	md5('ai-route-baseline-request:grammar_explain') ||
		md5('ai-route-baseline-request-2:grammar_explain'),
	'system:baseline',
	'Add grammar explanation fallback',
	'{}'::jsonb,
	'{
		"allowJsonResponse": true,
		"enabled": true,
		"maxInputCharacters": 12000,
		"maxMessages": 4,
		"maxOutputTokens": 1200,
		"model": "deepseek-v4-flash",
		"provider": "deepseek",
		"providerOptions": {"thinking": {"type": "disabled"}},
		"temperature": 0.2,
		"timeoutMs": 30000
	}'::jsonb
);--> statement-breakpoint
