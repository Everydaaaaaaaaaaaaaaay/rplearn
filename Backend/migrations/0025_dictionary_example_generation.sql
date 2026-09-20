CREATE TABLE app.dictionary_example_lexicon (
  lemma text PRIMARY KEY,
  definition text NOT NULL,
  meaning text NOT NULL,
  forms jsonb NOT NULL DEFAULT '[]',
  existing_examples jsonb NOT NULL DEFAULT '[]',
  source_version text NOT NULL,
  CHECK (jsonb_typeof(existing_examples) = 'array' AND jsonb_array_length(existing_examples) <= 2)
);
CREATE TABLE app.dictionary_example_generations (
  lemma text PRIMARY KEY REFERENCES app.dictionary_example_lexicon(lemma),
  revision integer NOT NULL DEFAULT 1,
  job_id uuid REFERENCES app.jobs(id) ON DELETE SET NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','ready','failed')),
  examples jsonb NOT NULL DEFAULT '[]',
  attempts integer NOT NULL DEFAULT 0,
  failure_code text,
  retry_after timestamptz,
  model text,
  prompt_version text NOT NULL DEFAULT 'learner-examples-runtime-v1',
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (jsonb_typeof(examples) = 'array' AND jsonb_array_length(examples) <= 2)
);
