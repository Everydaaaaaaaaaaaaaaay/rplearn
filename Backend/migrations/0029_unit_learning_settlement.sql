ALTER TABLE app.unit_learning_attempts
  ADD COLUMN scoring_version smallint NOT NULL DEFAULT 1
  CHECK (scoring_version IN (1, 2));
