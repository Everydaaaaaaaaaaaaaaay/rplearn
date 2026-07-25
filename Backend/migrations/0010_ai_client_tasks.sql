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
		'coach_review',
		'deepseek',
		'deepseek-v4-flash',
		12,
		16000,
		1200,
		0.2,
		true,
		45000,
		'{}'::jsonb
	),
	(
		'dictionary_explain',
		'deepseek',
		'deepseek-v4-flash',
		8,
		8000,
		800,
		0.2,
		false,
		30000,
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
