WITH "candidates" AS (
	SELECT *
	FROM "app"."ai_routes"
	WHERE "provider" = 'deepseek'
		AND "model" = 'deepseek-v4-flash'
		AND NOT ("provider_options" ? 'thinking')
	FOR UPDATE
),
"updated" AS (
	UPDATE "app"."ai_routes" AS "route"
	SET "provider_options" = "route"."provider_options" ||
			'{"thinking":{"type":"disabled"}}'::jsonb,
		"config_version" = "route"."config_version" + 1,
		"updated_at" = now()
	FROM "candidates"
	WHERE "route"."task" = "candidates"."task"
	RETURNING "route".*
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
	md5(
		'ai-route-explicit-mode-id:' || "updated"."task" || ':' ||
		"updated"."config_version"::text
	)::uuid,
	"updated"."task",
	"updated"."config_version",
	md5(
		'ai-route-explicit-mode-command:' || "updated"."task" || ':' ||
		"updated"."config_version"::text
	)::uuid,
	md5(
		'ai-route-explicit-mode-request:' || "updated"."task" || ':' ||
		"updated"."config_version"::text
	) || md5(
		'ai-route-explicit-mode-request-2:' || "updated"."task" || ':' ||
		"updated"."config_version"::text
	),
	'system:migration',
	'Preserve non-thinking behavior after moving tasks to DeepSeek V4 Flash',
	jsonb_build_object(
		'allowJsonResponse', "candidates"."allow_json_response",
		'enabled', "candidates"."enabled",
		'maxInputCharacters', "candidates"."max_input_characters",
		'maxMessages', "candidates"."max_messages",
		'maxOutputTokens', "candidates"."max_output_tokens",
		'model', "candidates"."model",
		'provider', "candidates"."provider",
		'providerOptions', "candidates"."provider_options",
		'temperature', "candidates"."temperature",
		'timeoutMs', "candidates"."timeout_ms"
	),
	jsonb_build_object(
		'allowJsonResponse', "updated"."allow_json_response",
		'enabled', "updated"."enabled",
		'maxInputCharacters', "updated"."max_input_characters",
		'maxMessages', "updated"."max_messages",
		'maxOutputTokens', "updated"."max_output_tokens",
		'model', "updated"."model",
		'provider', "updated"."provider",
		'providerOptions', "updated"."provider_options",
		'temperature', "updated"."temperature",
		'timeoutMs', "updated"."timeout_ms"
	)
FROM "updated"
JOIN "candidates" ON "candidates"."task" = "updated"."task";
