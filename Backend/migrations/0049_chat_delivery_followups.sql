CREATE TABLE app.chat_followups (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 message_id uuid NOT NULL, conversation_id uuid NOT NULL, character_id uuid NOT NULL,
 operation_id uuid NOT NULL DEFAULT gen_random_uuid(), request jsonb,
 lease_token uuid, lease_until timestamptz, completed_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,message_id)
);
--> statement-breakpoint
CREATE INDEX chat_followups_pending ON app.chat_followups(user_id,created_at) WHERE completed_at IS NULL;
--> statement-breakpoint
ALTER TABLE app.chat_generations ADD COLUMN voice_receipt jsonb;
--> statement-breakpoint
CREATE TABLE app.chat_voice_receipts (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 message_id uuid NOT NULL, heard_text text NOT NULL, interrupted boolean NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,message_id)
);
