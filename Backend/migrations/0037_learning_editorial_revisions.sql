CREATE TABLE app.learning_generation_edits (
  id uuid PRIMARY KEY,
  request_hash text NOT NULL,
  source_job_id uuid NOT NULL REFERENCES app.learning_generation_jobs(id),
  source_candidate_hash text NOT NULL,
  revised_job_id uuid NOT NULL UNIQUE REFERENCES app.learning_generation_jobs(id),
  blueprint_hash text NOT NULL,
  editor text NOT NULL CHECK (char_length(editor) BETWEEN 2 AND 60),
  notes text NOT NULL CHECK (char_length(notes) BETWEEN 30 AND 1000),
  payload jsonb NOT NULL CHECK (octet_length(payload::text) <= 131072),
  content_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (source_job_id, source_candidate_hash),
  CHECK (source_job_id <> revised_job_id)
);
