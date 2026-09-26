ALTER TABLE app.learning_generation_jobs
  ADD COLUMN lease_token uuid,
  ADD COLUMN candidate_hash text,
  ADD COLUMN blueprint_hash text,
  ADD COLUMN review_report jsonb,
  ADD COLUMN reviewed_by text,
  ADD COLUMN review_notes text,
  ADD COLUMN published_unit_id text REFERENCES app.learning_units(id);
--> statement-breakpoint
CREATE TABLE app.learning_generation_runs (
  job_id uuid NOT NULL REFERENCES app.learning_generation_jobs(id),
  attempt integer NOT NULL CHECK (attempt BETWEEN 1 AND 3),
  lease_token uuid NOT NULL,
  blueprint_hash text NOT NULL,
  prompt_version integer NOT NULL,
  candidate jsonb CHECK (octet_length(candidate::text)<=131072),
  review_report jsonb CHECK (octet_length(review_report::text)<=65536),
  author_model text,
  review_model text,
  author_usage jsonb,
  review_usage jsonb,
  outcome text NOT NULL DEFAULT 'running',
  error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  PRIMARY KEY (job_id, attempt)
);
CREATE INDEX learning_generation_daily_budget ON app.learning_generation_runs(created_at);
