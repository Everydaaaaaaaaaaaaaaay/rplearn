CREATE TABLE app.npc_activity_worlds (
  release_id text PRIMARY KEY,
  manifest_hash text NOT NULL CHECK (manifest_hash ~ '^[a-f0-9]{64}$'),
  manifest jsonb NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
CREATE TABLE app.npc_outings (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  run_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  release_id text NOT NULL REFERENCES app.npc_activity_worlds(release_id),
  city_id text NOT NULL,
  place_id text NOT NULL,
  status text NOT NULL CHECK (status IN ('reserved','opening_presented','in_progress','completed','abandoned')),
  snapshot jsonb NOT NULL CHECK (octet_length(snapshot::text) <= 262144),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, run_id)
);
--> statement-breakpoint
CREATE UNIQUE INDEX npc_outings_one_active ON app.npc_outings(user_id)
WHERE status IN ('reserved','opening_presented','in_progress');
--> statement-breakpoint
CREATE TABLE app.npc_outing_operations (
  user_id uuid NOT NULL,
  run_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, run_id, operation_id),
  FOREIGN KEY (user_id, run_id) REFERENCES app.npc_outings(user_id, run_id) ON DELETE CASCADE
);
--> statement-breakpoint
CREATE TABLE app.npc_outing_city_progress (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  city_id text NOT NULL,
  quiet_streak integer NOT NULL DEFAULT 0 CHECK (quiet_streak >= 0),
  familiar_streak integer NOT NULL DEFAULT 0 CHECK (familiar_streak >= 0),
  PRIMARY KEY (user_id, city_id)
);
