-- Learning evidence needs reliable structured output, independently of NPC chat tone.
INSERT INTO app.ai_routes(task, provider, model, enabled, allow_json_response,
  max_input_characters, max_messages, max_output_tokens, temperature, timeout_ms, provider_options)
VALUES ('learning_review', 'deepseek', 'deepseek-v4-flash', true, true,
  32000, 8, 2400, 0, 45000, '{"thinking":{"type":"disabled"}}'::jsonb)
ON CONFLICT (task) DO NOTHING;
