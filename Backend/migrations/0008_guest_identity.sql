CREATE TABLE app.guest_installations (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  installation_hash char(64) NOT NULL UNIQUE,
  claimed_by_user_id uuid REFERENCES app.users(id) ON DELETE SET NULL,
  claimed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
