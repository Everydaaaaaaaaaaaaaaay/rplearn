CREATE TABLE app.learning_audio_assets (
  id text PRIMARY KEY,
  sha256 text NOT NULL,
  metadata jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT learning_audio_content_address CHECK (id = 'audio.' || sha256)
);
