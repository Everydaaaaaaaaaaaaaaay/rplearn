CREATE TABLE app.learning_image_assets (
  id text PRIMARY KEY,
  sha256 text NOT NULL,
  metadata jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT learning_image_content_address CHECK (id = 'image.' || sha256)
);
