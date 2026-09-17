-- DeepSeek 把标准模型名统一为 deepseek-flash：deepseek-v4-flash 与
-- deepseek-v4-flash-vision-exp 已退役（仍按 Flash 计价，请求由 V4.1-Flash 承载）。
-- 这里把指向退役名字的 DeepSeek 路由改成标准名，并按控制台口径同步
-- config_version 与 ai_route_revisions；已经是 deepseek-flash 时不改配置、不新增版本记录。
WITH changed AS (
	UPDATE "app"."ai_routes"
	SET
		"model" = 'deepseek-flash',
		"config_version" = "config_version" + 1,
		"updated_at" = now()
	WHERE
		"provider" = 'deepseek'
		AND "model" IN ('deepseek-v4-flash', 'deepseek-v4-flash-vision-exp')
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
	md5('ai-route-deepseek-flash-id:' || changed."task" || ':' || changed."config_version")::uuid,
	changed."task",
	changed."config_version",
	md5('ai-route-deepseek-flash-command:' || changed."task" || ':' || changed."config_version")::uuid,
	md5('ai-route-deepseek-flash-request:' || changed."task" || ':' || changed."config_version") ||
		md5('ai-route-deepseek-flash-request-2:' || changed."task" || ':' || changed."config_version"),
	'system:migration',
	'Adopt the canonical DeepSeek model name deepseek-flash',
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
