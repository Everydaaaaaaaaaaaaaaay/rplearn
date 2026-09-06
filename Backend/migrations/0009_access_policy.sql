INSERT INTO app.service_metadata (key, value) VALUES ('guest-access-policy-v1',
  '{"friendSlotLimit":3,"chatLimit":12,"voiceSecondsLimit":60,"advancedLimit":1,"policyVersion":1,"provisional":true}')
ON CONFLICT (key) DO NOTHING;
--> statement-breakpoint
UPDATE app.billing_plans SET feature_flags = feature_flags || '{"friendSlotLimit":5}'::jsonb,
  updated_at = now() WHERE tier = 'free';
--> statement-breakpoint
ALTER TABLE app.user_profiles ALTER COLUMN friend_slot_limit SET DEFAULT 5;
--> statement-breakpoint
UPDATE app.user_profiles SET friend_slot_limit = 5 WHERE friend_slot_limit = 3
  AND NOT EXISTS (SELECT 1 FROM app.guest_installations g WHERE g.user_id = app.user_profiles.user_id)
  AND NOT EXISTS (SELECT 1 FROM app.ai_guest_principals g WHERE g.user_id = app.user_profiles.user_id);
