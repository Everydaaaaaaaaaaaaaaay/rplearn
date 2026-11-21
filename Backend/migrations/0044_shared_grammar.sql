CREATE TABLE app.shared_grammar_concepts (
  id text PRIMARY KEY,
  identity text NOT NULL UNIQUE,
  pattern_fingerprint text NOT NULL UNIQUE CHECK (length(pattern_fingerprint) = 64),
  point jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE app.shared_grammar_aliases (
  fingerprint text PRIMARY KEY CHECK (length(fingerprint) = 64),
  concept_id text,
  proposal jsonb,
  reviewed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
-- New tasks inherit the currently managed provider; existing grammar routing is unchanged.
INSERT INTO app.ai_routes(task,provider,model,max_messages,max_input_characters,max_output_tokens,
  temperature,allow_json_response,timeout_ms,provider_options)
SELECT t.task,r.provider,r.model,4,64000,t.budget,0.2,true,60000,r.provider_options
FROM app.ai_routes r CROSS JOIN (VALUES ('grammar_analysis',3200),('grammar_library_review',2200)) AS t(task,budget)
WHERE r.task = 'grammar_explain' ON CONFLICT (task) DO NOTHING;
--> statement-breakpoint
INSERT INTO app.ai_route_revisions(id,task,config_version,command_id,request_hash,operator_key_id,
  change_reason,previous_config,new_config)
SELECT md5('shared-grammar-route:' || task)::uuid,task,1,md5('shared-grammar-command:' || task)::uuid,
  md5('shared-grammar-request:' || task) || md5('shared-grammar-request-2:' || task),
  'system:baseline','Add shared grammar analysis and independent curation','{}'::jsonb,
  jsonb_build_object('allowJsonResponse',true,'enabled',true,'maxInputCharacters',max_input_characters,
    'maxMessages',max_messages,'maxOutputTokens',max_output_tokens,'model',model,'provider',provider,
    'providerOptions',provider_options,'temperature',temperature,'timeoutMs',timeout_ms)
FROM app.ai_routes WHERE task IN ('grammar_analysis','grammar_library_review')
ON CONFLICT DO NOTHING;
