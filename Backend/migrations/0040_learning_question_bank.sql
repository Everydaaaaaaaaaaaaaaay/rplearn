CREATE TABLE app.learning_bank_questions (
  id text PRIMARY KEY,
  current_version integer NOT NULL CHECK (current_version > 0),
  material_hash text NOT NULL UNIQUE,
  published boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE app.learning_bank_versions (
  question_id text NOT NULL REFERENCES app.learning_bank_questions(id),
  version integer NOT NULL,
  payload jsonb NOT NULL,
  content_hash text NOT NULL,
  operator text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (question_id, version)
);
CREATE TABLE app.learning_bank_sources (
  unit_id text NOT NULL,
  unit_version integer NOT NULL,
  local_question_id text NOT NULL,
  question_id text NOT NULL REFERENCES app.learning_bank_questions(id),
  PRIMARY KEY (unit_id, unit_version, local_question_id),
  FOREIGN KEY (unit_id, unit_version) REFERENCES app.learning_unit_versions(unit_id,version) ON DELETE CASCADE
);
CREATE TABLE app.learning_bank_blueprints (
  id text PRIMARY KEY,
  payload jsonb NOT NULL,
  published boolean NOT NULL DEFAULT true
);
--> statement-breakpoint
ALTER TABLE app.learning_attempts ALTER COLUMN unit_id DROP NOT NULL;
ALTER TABLE app.learning_attempts ALTER COLUMN unit_version DROP NOT NULL;
ALTER TABLE app.learning_attempts ADD COLUMN snapshot jsonb;
ALTER TABLE app.learning_attempts ADD COLUMN blueprint_id text REFERENCES app.learning_bank_blueprints(id);
ALTER TABLE app.learning_attempts ADD CONSTRAINT learning_attempt_content CHECK (
  (unit_id IS NOT NULL AND unit_version IS NOT NULL AND snapshot IS NULL) OR
  (unit_id IS NULL AND unit_version IS NULL AND snapshot IS NOT NULL)
);
CREATE TABLE app.learning_bank_exposures (
  attempt_id uuid NOT NULL REFERENCES app.learning_attempts(id) ON DELETE CASCADE,
  local_question_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  question_id text NOT NULL REFERENCES app.learning_bank_questions(id),
  version integer NOT NULL,
  PRIMARY KEY(attempt_id,local_question_id),
  FOREIGN KEY(question_id,version) REFERENCES app.learning_bank_versions(question_id,version)
);
CREATE INDEX learning_bank_seen ON app.learning_bank_exposures(user_id,question_id);
CREATE TABLE app.learning_bank_mastery (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  question_id text NOT NULL REFERENCES app.learning_bank_questions(id),
  first_attempt_id uuid REFERENCES app.learning_attempts(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,question_id)
);
CREATE TABLE app.learning_bank_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  question_id text NOT NULL REFERENCES app.learning_bank_questions(id),
  version integer NOT NULL,
  operation text NOT NULL,
  operator text NOT NULL,
  notes text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
ALTER TABLE app.learning_rewards DROP CONSTRAINT learning_rewards_points_check;
ALTER TABLE app.learning_rewards ADD CONSTRAINT learning_rewards_points_check CHECK (points IN (0,1));

--> statement-breakpoint
CREATE TABLE app.learning_bank_control (id boolean PRIMARY KEY DEFAULT true CHECK (id), enabled boolean NOT NULL DEFAULT false);
INSERT INTO app.learning_bank_control(id,enabled) VALUES(true,false);
