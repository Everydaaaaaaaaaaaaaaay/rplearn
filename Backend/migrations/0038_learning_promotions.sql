CREATE TABLE app.learning_promotions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  from_level app.difficulty_level NOT NULL,
  to_level app.difficulty_level NOT NULL,
  course_hash text NOT NULL CHECK (course_hash ~ '^[a-f0-9]{64}$'),
  course jsonb NOT NULL CHECK (octet_length(course::text) <= 131072),
  status text NOT NULL DEFAULT 'started' CHECK (status IN ('started','completed','superseded')),
  acknowledged_beats integer NOT NULL DEFAULT 0 CHECK (acknowledged_beats >= 0),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  profile_version integer NOT NULL CHECK (profile_version > 0),
  completed_profile_version integer,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  CHECK (from_level <> to_level),
  CHECK ((status = 'completed') = (completed_at IS NOT NULL)),
  CHECK ((status = 'completed') = (completed_profile_version IS NOT NULL))
);
CREATE UNIQUE INDEX learning_one_level_promotion ON app.learning_promotions(user_id,from_level) WHERE status IN ('started','completed');
