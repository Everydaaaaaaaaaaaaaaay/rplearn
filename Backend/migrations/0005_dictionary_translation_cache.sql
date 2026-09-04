CREATE TYPE "app"."dictionary_translation_status" AS ENUM('pending', 'ready', 'failed');--> statement-breakpoint
CREATE TABLE "app"."dictionary_example_translations" (
	"attempt_count" integer DEFAULT 1 NOT NULL,
	"cache_key" text PRIMARY KEY NOT NULL,
	"candidate_meanings_zh_hans" jsonb NOT NULL,
	"completed_at" timestamp with time zone,
	"contextual_meaning_zh_hans" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"dictionary_source" text NOT NULL,
	"dictionary_version" text NOT NULL,
	"example_hash" text NOT NULL,
	"failure_code" text,
	"generation_kind" text NOT NULL,
	"lemma" text NOT NULL,
	"part_of_speech" text NOT NULL,
	"prompt_version" text NOT NULL,
	"requested_by_user_id" uuid,
	"selected_meaning_index" integer,
	"sense_definition_en" text,
	"sense_fingerprint" text NOT NULL,
	"sentence" text NOT NULL,
	"sentence_zh_hans" text,
	"source_key" text NOT NULL,
	"stable_sense_id" text,
	"status" "app"."dictionary_translation_status" DEFAULT 'pending' NOT NULL,
	"translation_model_version" text NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL,
	CONSTRAINT "dictionary_translations_cache_key_length" CHECK (length("app"."dictionary_example_translations"."cache_key") = 64),
	CONSTRAINT "dictionary_translations_source_key_length" CHECK (length("app"."dictionary_example_translations"."source_key") = 64),
	CONSTRAINT "dictionary_translations_example_hash_length" CHECK (length("app"."dictionary_example_translations"."example_hash") = 64),
	CONSTRAINT "dictionary_translations_sense_hash_length" CHECK (length("app"."dictionary_example_translations"."sense_fingerprint") = 64),
	CONSTRAINT "dictionary_translations_attempt_positive" CHECK ("app"."dictionary_example_translations"."attempt_count" > 0),
	CONSTRAINT "dictionary_translations_generation_kind" CHECK ("app"."dictionary_example_translations"."generation_kind" in ('runtime', 'trusted_precomputed')),
	CONSTRAINT "dictionary_translations_ready_output" CHECK ((
        "app"."dictionary_example_translations"."status" = 'ready'
        and "app"."dictionary_example_translations"."sentence_zh_hans" is not null
        and "app"."dictionary_example_translations"."contextual_meaning_zh_hans" is not null
        and "app"."dictionary_example_translations"."completed_at" is not null
      ) or (
        "app"."dictionary_example_translations"."status" <> 'ready'
        and "app"."dictionary_example_translations"."sentence_zh_hans" is null
        and "app"."dictionary_example_translations"."contextual_meaning_zh_hans" is null
        and "app"."dictionary_example_translations"."selected_meaning_index" is null
      ))
);
--> statement-breakpoint
ALTER TABLE "app"."dictionary_example_translations" ADD CONSTRAINT "dictionary_example_translations_requested_by_user_id_users_id_fk" FOREIGN KEY ("requested_by_user_id") REFERENCES "app"."users"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "dictionary_translations_source_status_index" ON "app"."dictionary_example_translations" USING btree ("source_key","status","generation_kind","completed_at");--> statement-breakpoint
CREATE INDEX "dictionary_translations_status_updated_index" ON "app"."dictionary_example_translations" USING btree ("status","updated_at");--> statement-breakpoint
CREATE INDEX "dictionary_translations_requester_index" ON "app"."dictionary_example_translations" USING btree ("requested_by_user_id","created_at");
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
	'dictionary_example_translation',
	'deepseek',
	'deepseek-v4-flash',
	2,
	8000,
	500,
	0.1,
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
	md5('ai-route-baseline-id:dictionary_example_translation')::uuid,
	'dictionary_example_translation',
	1,
	md5('ai-route-baseline-command:dictionary_example_translation')::uuid,
	md5('ai-route-baseline-request:dictionary_example_translation') ||
		md5('ai-route-baseline-request-2:dictionary_example_translation'),
	'system:baseline',
	'Add asynchronous dictionary example translation',
	'{}'::jsonb,
	'{
		"allowJsonResponse": true,
		"enabled": true,
		"maxInputCharacters": 8000,
		"maxMessages": 2,
		"maxOutputTokens": 500,
		"model": "deepseek-v4-flash",
		"provider": "deepseek",
		"providerOptions": {"thinking": {"type": "disabled"}},
		"temperature": 0.1,
		"timeoutMs": 30000
	}'::jsonb
);
