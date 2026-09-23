CREATE TABLE app.learning_states (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  payload text NOT NULL CHECK (octet_length(payload) <= 2097152),
  updated_at timestamptz NOT NULL DEFAULT now()
);
