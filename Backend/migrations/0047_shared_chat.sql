CREATE TABLE app.chat_sessions (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 character_id uuid NOT NULL, conversation_id uuid NOT NULL,
 last_sequence integer NOT NULL DEFAULT 0, revision bigint NOT NULL DEFAULT 1,
 created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id,character_id),
 UNIQUE(user_id,conversation_id)
);
--> statement-breakpoint
CREATE TABLE app.chat_aliases (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 conversation_id uuid NOT NULL, canonical_id uuid NOT NULL,
 PRIMARY KEY(user_id,conversation_id)
);
--> statement-breakpoint
CREATE TABLE app.chat_generations (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 conversation_id uuid NOT NULL, status text NOT NULL CHECK(status IN ('queued','dispatched','completed','failed','uncertain')),
 available_at timestamptz NOT NULL DEFAULT now(), lease_until timestamptz, fence_token uuid,
 input_message_ids uuid[] NOT NULL DEFAULT '{}', snapshot jsonb,
 partial_text text NOT NULL DEFAULT '', error_code text,
 created_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz
);
--> statement-breakpoint
CREATE UNIQUE INDEX chat_one_producer ON app.chat_generations(user_id,conversation_id) WHERE status IN ('queued','dispatched');
--> statement-breakpoint
CREATE TABLE app.chat_messages (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 message_id uuid NOT NULL, conversation_id uuid NOT NULL, sequence integer NOT NULL,
 role text NOT NULL CHECK(role IN ('user','assistant','coach')), protected_payload jsonb NOT NULL,
 assigned_generation_id uuid REFERENCES app.chat_generations(id),
 answered_by uuid REFERENCES app.chat_generations(id),
 PRIMARY KEY(user_id,message_id), UNIQUE(user_id,conversation_id,sequence)
);
--> statement-breakpoint
CREATE INDEX chat_pending_messages ON app.chat_messages(user_id,conversation_id,sequence) WHERE role='user' AND answered_by IS NULL AND assigned_generation_id IS NULL;
--> statement-breakpoint
CREATE TABLE app.chat_retry_commands (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 command_id uuid NOT NULL, conversation_id uuid NOT NULL, generation_id uuid NOT NULL REFERENCES app.chat_generations(id),
 PRIMARY KEY(user_id,command_id)
);
