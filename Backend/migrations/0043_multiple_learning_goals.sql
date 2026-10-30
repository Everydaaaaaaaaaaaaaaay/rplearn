-- Nullable addition keeps existing profiles and rollback code compatible.
-- Existing single selections are projected as a one-element list on read.
ALTER TABLE "app"."user_profiles"
  ADD COLUMN "learning_goals" "app"."learning_goal"[];--> statement-breakpoint
ALTER TABLE "app"."user_profiles"
  ADD CONSTRAINT "user_profiles_learning_goals_nonempty"
  CHECK ("learning_goals" IS NULL OR
    (cardinality("learning_goals") BETWEEN 1 AND 7 AND array_position("learning_goals", NULL) IS NULL));
