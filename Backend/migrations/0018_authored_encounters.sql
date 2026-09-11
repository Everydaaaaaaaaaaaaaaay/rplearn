CREATE TABLE app.npc_library_versions (
  version text PRIMARY KEY,
  manifest_hash text NOT NULL CHECK (manifest_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now()
);
--> statement-breakpoint
ALTER TABLE app.npc_scene_affinities ADD COLUMN library_version text REFERENCES app.npc_library_versions(version);
--> statement-breakpoint
CREATE TABLE app.npc_authored_encounter_runs (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  run_id uuid NOT NULL,
  request_hash text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  selection jsonb NOT NULL CHECK (octet_length(selection::text) <= 65536),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, run_id)
);
