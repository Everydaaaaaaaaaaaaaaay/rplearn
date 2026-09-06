CREATE TABLE app.npc_scene_affinities (
  npc_id uuid NOT NULL REFERENCES app.public_npcs(id) ON DELETE CASCADE,
  region_id text NOT NULL,
  activity_id text NOT NULL,
  category text NOT NULL,
  language text NOT NULL,
  PRIMARY KEY (npc_id, region_id, activity_id, language)
);
--> statement-breakpoint
CREATE INDEX npc_scene_lookup ON app.npc_scene_affinities(region_id, activity_id, language);
--> statement-breakpoint
CREATE TABLE app.npc_encounter_history (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  npc_id uuid NOT NULL REFERENCES app.public_npcs(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  encounters integer NOT NULL DEFAULT 1,
  PRIMARY KEY (user_id, npc_id)
);
--> statement-breakpoint
CREATE TABLE app.npc_scene_supply (
  region_id text NOT NULL,
  activity_id text NOT NULL,
  language text NOT NULL,
  selections integer NOT NULL DEFAULT 0,
  reuses integer NOT NULL DEFAULT 0,
  gaps integer NOT NULL DEFAULT 0,
  candidate_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (region_id, activity_id, language)
);
