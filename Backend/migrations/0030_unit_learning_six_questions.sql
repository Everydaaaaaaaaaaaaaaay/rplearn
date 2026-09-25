ALTER TABLE app.unit_learning_attempts
  DROP CONSTRAINT unit_learning_attempts_scoring_version_check;

ALTER TABLE app.unit_learning_attempts
  ADD CONSTRAINT unit_learning_attempts_scoring_version_check
  CHECK (scoring_version IN (1, 2, 3));

INSERT INTO app.ai_routes(task, provider, model, enabled, allow_json_response,
  max_input_characters, max_messages, max_output_tokens, temperature, timeout_ms, provider_options)
SELECT 'unit_authoring', provider, model, enabled, allow_json_response,
  max_input_characters, max_messages, 4800, 0.2, 60000, provider_options
FROM app.ai_routes WHERE task = 'learning_review'
ON CONFLICT (task) DO NOTHING;
