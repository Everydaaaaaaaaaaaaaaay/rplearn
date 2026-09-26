CREATE TABLE app.learning_characters (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  character_id uuid NOT NULL,
  role_key text NOT NULL,
  cycle_id uuid NOT NULL,
  characters integer NOT NULL DEFAULT 0 CHECK (characters BETWEEN 0 AND 1000),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  PRIMARY KEY (user_id, character_id)
);
--> statement-breakpoint
CREATE TABLE app.learning_units (
  id text PRIMARY KEY,
  role_key text NOT NULL,
  level_key app.difficulty_level NOT NULL,
  current_version integer NOT NULL CHECK (current_version > 0),
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX learning_units_pool ON app.learning_units (role_key, level_key) WHERE published;
--> statement-breakpoint
CREATE TABLE app.learning_unit_versions (
  unit_id text NOT NULL REFERENCES app.learning_units(id),
  version integer NOT NULL CHECK (version > 0),
  payload jsonb NOT NULL CHECK (octet_length(payload::text) <= 131072),
  content_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (unit_id, version)
);
--> statement-breakpoint
CREATE TABLE app.learning_attempts (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  character_id uuid NOT NULL,
  cycle_id uuid NOT NULL,
  unit_id text NOT NULL,
  unit_version integer NOT NULL,
  level_key app.difficulty_level NOT NULL,
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  started_at timestamptz NOT NULL DEFAULT now(),
  first_completed_at timestamptz,
  FOREIGN KEY (user_id, character_id) REFERENCES app.learning_characters(user_id, character_id) ON DELETE CASCADE,
  FOREIGN KEY (unit_id, unit_version) REFERENCES app.learning_unit_versions(unit_id, version),
  UNIQUE (user_id, character_id, unit_id),
  UNIQUE (user_id, character_id, cycle_id)
);
CREATE UNIQUE INDEX learning_one_active_attempt ON app.learning_attempts(user_id, character_id) WHERE first_completed_at IS NULL;
CREATE INDEX learning_attempt_history ON app.learning_attempts(user_id, character_id, started_at DESC, id DESC);
--> statement-breakpoint
CREATE TABLE app.learning_rounds (
  id uuid PRIMARY KEY,
  attempt_id uuid NOT NULL REFERENCES app.learning_attempts(id) ON DELETE CASCADE,
  ordinal integer NOT NULL CHECK (ordinal >= 0),
  question_ids text[] NOT NULL CHECK (cardinality(question_ids) > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE (attempt_id, ordinal)
);
CREATE UNIQUE INDEX learning_one_active_round ON app.learning_rounds(attempt_id) WHERE completed_at IS NULL;
--> statement-breakpoint
CREATE TABLE app.learning_answers (
  round_id uuid NOT NULL REFERENCES app.learning_rounds(id) ON DELETE CASCADE,
  question_id text NOT NULL,
  answer jsonb NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (round_id, question_id)
);
CREATE TABLE app.learning_rewards (
  attempt_id uuid NOT NULL REFERENCES app.learning_attempts(id) ON DELETE CASCADE,
  question_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  level_key app.difficulty_level NOT NULL,
  goal_id text NOT NULL,
  points integer NOT NULL CHECK (points = 1),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (attempt_id, question_id)
);
CREATE INDEX learning_rewards_account_level ON app.learning_rewards(user_id, level_key);
--> statement-breakpoint
CREATE TABLE app.learning_level_progress (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  level_key app.difficulty_level NOT NULL,
  points integer NOT NULL DEFAULT 0 CHECK (points >= 0),
  PRIMARY KEY (user_id, level_key)
);
CREATE TABLE app.learning_milestones (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  level_key app.difficulty_level NOT NULL,
  star integer NOT NULL CHECK (star BETWEEN 1 AND 9),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, level_key, star)
);
--> statement-breakpoint
CREATE TABLE app.learning_message_events (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL,
  character_id uuid NOT NULL,
  cycle_id uuid NOT NULL,
  character_count integer NOT NULL CHECK (character_count >= 0),
  accepted boolean NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, message_id),
  FOREIGN KEY (user_id, character_id) REFERENCES app.learning_characters(user_id, character_id) ON DELETE CASCADE
);
CREATE TABLE app.learning_receipts (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  request_id uuid NOT NULL,
  operation text NOT NULL,
  request_hash text NOT NULL,
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, request_id)
);
--> statement-breakpoint
CREATE TABLE app.learning_generation_jobs (
  id uuid PRIMARY KEY,
  role_key text NOT NULL,
  level_key app.difficulty_level NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'review', 'published', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_until timestamptz,
  candidate jsonb,
  last_error_code text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX learning_one_pool_generation ON app.learning_generation_jobs(role_key, level_key) WHERE status IN ('pending', 'running', 'review');
