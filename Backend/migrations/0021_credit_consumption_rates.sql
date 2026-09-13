CREATE TABLE app.credit_rate_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  version integer NOT NULL DEFAULT 1,
  rate_units integer NOT NULL DEFAULT 10000 CHECK (rate_units BETWEEN 0 AND 1000000)
);
INSERT INTO app.credit_rate_policy(singleton) VALUES (true);
--> statement-breakpoint
CREATE TABLE app.credit_rate_overrides (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  rate_units integer NOT NULL CHECK (rate_units BETWEEN 0 AND 1000000),
  updated_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE app.credit_rate_changes (
  command_id uuid PRIMARY KEY,
  version integer NOT NULL UNIQUE,
  operator_key_id text NOT NULL,
  reason text NOT NULL,
  request jsonb NOT NULL,
  previous jsonb NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
ALTER TABLE app.credit_operations
  ADD COLUMN rate_units integer NOT NULL DEFAULT 10000 CHECK (rate_units BETWEEN 0 AND 1000000),
  ADD COLUMN rate_version integer,
  ADD COLUMN raw_settled_units numeric(24,0);
