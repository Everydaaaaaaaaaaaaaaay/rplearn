CREATE INDEX chat_generation_history ON app.chat_generations(user_id,conversation_id,created_at DESC,id DESC);
--> statement-breakpoint
CREATE INDEX chat_generation_ready ON app.chat_generations(available_at,id) WHERE status IN ('queued','dispatched','uncertain');
--> statement-breakpoint
CREATE INDEX chat_generation_assignments ON app.chat_messages(assigned_generation_id) WHERE assigned_generation_id IS NOT NULL;
