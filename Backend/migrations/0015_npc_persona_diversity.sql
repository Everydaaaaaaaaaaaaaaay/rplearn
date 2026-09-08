ALTER TABLE app.npc_pending_avatars
  ADD COLUMN persona_profile jsonb,
  ADD COLUMN persona_signature text;
--> statement-breakpoint
ALTER TABLE app.public_npcs
  ADD COLUMN persona_profile jsonb,
  ADD COLUMN persona_signature text;
--> statement-breakpoint
CREATE UNIQUE INDEX npc_pending_avatars_persona_signature_unique
  ON app.npc_pending_avatars(persona_signature);
--> statement-breakpoint
CREATE UNIQUE INDEX public_npcs_persona_signature_unique
  ON app.public_npcs(persona_signature);
--> statement-breakpoint
CREATE INDEX npc_pending_avatars_region_id_index
  ON app.npc_pending_avatars((input->'card'->>'regionId'));
--> statement-breakpoint
CREATE INDEX public_npcs_region_id_index
  ON app.public_npcs((card->>'regionId'));
--> statement-breakpoint
ALTER TABLE app.npc_pending_avatars
  ADD CONSTRAINT npc_pending_avatars_persona_signature_format
    CHECK (persona_signature IS NULL OR persona_signature ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT npc_pending_avatars_persona_profile_size
    CHECK (persona_profile IS NULL OR octet_length(persona_profile::text) <= 4096);
--> statement-breakpoint
ALTER TABLE app.public_npcs
  ADD CONSTRAINT public_npcs_persona_signature_format
    CHECK (persona_signature IS NULL OR persona_signature ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT public_npcs_persona_profile_size
    CHECK (persona_profile IS NULL OR octet_length(persona_profile::text) <= 4096);
