ALTER TABLE app.store_products ADD COLUMN coin_amount integer NOT NULL DEFAULT 0 CHECK (coin_amount >= 0);
--> statement-breakpoint
ALTER TABLE app.store_products ADD COLUMN ticket_count integer NOT NULL DEFAULT 0 CHECK (ticket_count >= 0);
--> statement-breakpoint
CREATE TABLE app.billing_asset_grants (
  environment app.billing_environment NOT NULL,
  transaction_id text NOT NULL,
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  coins integer NOT NULL CHECK (coins >= 0),
  ticket_ids uuid[] NOT NULL DEFAULT '{}',
  revoked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (environment, transaction_id)
);
--> statement-breakpoint
CREATE TABLE app.coin_adjustment_debts (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  coins integer NOT NULL DEFAULT 0 CHECK (coins >= 0)
);
--> statement-breakpoint
UPDATE app.store_products SET ticket_count = CASE
  WHEN product_id = 'com.tiantian.lingotrip.plus.monthly' THEN 1
  WHEN product_id = 'com.tiantian.lingotrip.pro.monthly' THEN 2
  WHEN product_id = 'com.tiantian.lingotrip.plus.yearly' THEN 12
  WHEN product_id = 'com.tiantian.lingotrip.pro.yearly' THEN 24 ELSE 0 END
WHERE provider = 'apple';
--> statement-breakpoint
INSERT INTO app.store_products(provider, product_id, plan_id, coin_amount)
VALUES ('apple', 'com.tiantian.lingotrip.coins.500', 'free', 500),
       ('apple', 'com.tiantian.lingotrip.coins.1800', 'free', 1800),
       ('apple', 'com.tiantian.lingotrip.coins.3500', 'free', 3500)
ON CONFLICT (provider, product_id) DO NOTHING;

--> statement-breakpoint
CREATE TABLE app.story_reward_claims (
 user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
 story_id text NOT NULL,
 reward_coins integer NOT NULL,
 PRIMARY KEY(user_id,story_id)
);
