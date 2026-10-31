CREATE TABLE app.appointments (
 id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 character_id text NOT NULL, conversation_id text NOT NULL, evidence_hash text NOT NULL,
 snapshot jsonb NOT NULL, session jsonb, summary jsonb, evidence jsonb NOT NULL,
 review_operation_id uuid, review_lease_until timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(user_id,character_id,evidence_hash)
);
--> statement-breakpoint
CREATE INDEX appointments_owner ON app.appointments(user_id,created_at DESC);
--> statement-breakpoint
CREATE TABLE app.appointment_operations (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE, command_id uuid NOT NULL,
 appointment_id uuid REFERENCES app.appointments(id) ON DELETE CASCADE,
 kind text NOT NULL, request_hash text NOT NULL, status text NOT NULL CHECK(status IN ('running','failed','completed')),
 lease_token uuid, lease_until timestamptz, recoverable boolean NOT NULL DEFAULT false, context jsonb, draft jsonb, response jsonb,
 created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(user_id,command_id)
);
--> statement-breakpoint
CREATE UNIQUE INDEX appointment_one_running ON app.appointment_operations(appointment_id) WHERE status='running';
--> statement-breakpoint
CREATE TABLE app.appointment_settlements (
 appointment_id uuid PRIMARY KEY REFERENCES app.appointments(id) ON DELETE CASCADE,
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 review jsonb NOT NULL, status text NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','settled')),
 evidence_hash text NOT NULL, receipt jsonb, created_at timestamptz NOT NULL DEFAULT now(), settled_at timestamptz
);
--> statement-breakpoint
INSERT INTO app.ai_routes(task,provider,model,max_messages,max_input_characters,max_output_tokens,temperature,allow_json_response,timeout_ms,provider_options,enabled)
SELECT stage.task,r.provider,r.model,8,500000,case when stage.task in ('appointment_story','appointment_story_retry') then 6000 else 3000 end,r.temperature,true,120000,r.provider_options,r.enabled
FROM app.ai_routes r CROSS JOIN (VALUES ('appointment_detection'),('appointment_story'),('appointment_story_retry'),('appointment_review')) stage(task)
WHERE r.task='coach_review'
ON CONFLICT(task) DO NOTHING;
