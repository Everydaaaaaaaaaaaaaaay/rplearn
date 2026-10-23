-- Preserve withdrawn attempts, their answers and rewards without calling them completed.
ALTER TABLE app.learning_attempts ADD COLUMN superseded_at timestamptz;
--> statement-breakpoint
DROP INDEX app.learning_one_active_attempt;
--> statement-breakpoint
CREATE UNIQUE INDEX learning_one_active_attempt ON app.learning_attempts(user_id, character_id)
  WHERE first_completed_at IS NULL AND superseded_at IS NULL;
