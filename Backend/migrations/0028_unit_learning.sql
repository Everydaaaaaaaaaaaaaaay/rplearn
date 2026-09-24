CREATE TABLE app.unit_learning_accounts (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  grade smallint NOT NULL DEFAULT 1 CHECK (grade BETWEEN 1 AND 12),
  grade_correct smallint NOT NULL DEFAULT 0 CHECK (grade_correct BETWEEN 0 AND 90),
  completed_levels integer NOT NULL DEFAULT 0,
  source_difficulty text NOT NULL DEFAULT 'primary1',
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE app.unit_learning_characters (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  character_id uuid NOT NULL,
  role_key text NOT NULL,
  chat_characters integer NOT NULL DEFAULT 0 CHECK (chat_characters BETWEEN 0 AND 1000),
  active_attempt_id uuid,
  PRIMARY KEY (user_id, character_id)
);

CREATE TABLE app.unit_learning_messages (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL,
  character_id uuid NOT NULL,
  character_count integer NOT NULL,
  PRIMARY KEY (user_id, message_id)
);

CREATE TABLE app.unit_learning_templates (
  id text PRIMARY KEY,
  role_key text NOT NULL,
  grade smallint NOT NULL CHECK (grade BETWEEN 1 AND 12),
  source text NOT NULL CHECK (source IN ('authored', 'generated')),
  scope_user_id uuid REFERENCES app.users(id) ON DELETE CASCADE,
  version integer NOT NULL DEFAULT 1,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX unit_learning_templates_pool ON app.unit_learning_templates(role_key, grade, scope_user_id);

CREATE TABLE app.unit_learning_attempts (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  character_id uuid NOT NULL,
  template_id text NOT NULL REFERENCES app.unit_learning_templates(id),
  grade smallint NOT NULL CHECK (grade BETWEEN 1 AND 12),
  answers jsonb NOT NULL DEFAULT '{}'::jsonb,
  correct_question_ids text[] NOT NULL DEFAULT '{}',
  completed_at timestamptz,
  started_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX unit_learning_attempts_history ON app.unit_learning_attempts(user_id, character_id, started_at DESC);
