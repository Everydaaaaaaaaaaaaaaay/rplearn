WITH changed AS (
	UPDATE "app"."ai_routes"
	SET
		"max_output_tokens" = 2400,
		"config_version" = "config_version" + 1,
		"updated_at" = now()
	WHERE
		"task" = 'translation'
		AND "max_output_tokens" <> 2400
	RETURNING
		"allow_json_response",
		"config_version",
		"enabled",
		"max_input_characters",
		"max_messages",
		"max_output_tokens",
		"model",
		"provider",
		"provider_options",
		"task",
		"temperature",
		"timeout_ms"
)
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
	md5('ai-route-output-limit-id:' || changed."task" || ':' || changed."config_version")::uuid,
	changed."task",
	changed."config_version",
	md5('ai-route-output-limit-command:' || changed."task" || ':' || changed."config_version")::uuid,
	md5('ai-route-output-limit-request:' || changed."task" || ':' || changed."config_version") ||
		md5('ai-route-output-limit-request-2:' || changed."task" || ':' || changed."config_version"),
	'system:migration',
	'Raise translation output limit to 2400 like the other managed routes',
	coalesce(prior."new_config", '{}'::jsonb),
	jsonb_build_object(
		'allowJsonResponse', changed."allow_json_response",
		'enabled', changed."enabled",
		'maxInputCharacters', changed."max_input_characters",
		'maxMessages', changed."max_messages",
		'maxOutputTokens', changed."max_output_tokens",
		'model', changed."model",
		'provider', changed."provider",
		'providerOptions', changed."provider_options",
		'temperature', changed."temperature",
		'timeoutMs', changed."timeout_ms"
	)
FROM changed
LEFT JOIN "app"."ai_route_revisions" AS prior
	ON prior."task" = changed."task"
	AND prior."config_version" = changed."config_version" - 1;--> statement-breakpoint
