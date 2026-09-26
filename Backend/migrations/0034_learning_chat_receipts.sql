-- 消息保存与候选事件同事务。候选正文仅用于核对完整回复，处理后立即去除。
CREATE TABLE app.learning_chat_outbox (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  message_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  character_id uuid NOT NULL,
  origin jsonb NOT NULL,
  body text,
  body_fingerprint text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz,
  checked_at timestamptz NOT NULL DEFAULT '-infinity',
  outcome text CHECK(outcome IN ('counted','ignored','invalid','expired')),
  PRIMARY KEY(user_id,message_id)
);
CREATE INDEX learning_chat_pending ON app.learning_chat_outbox(created_at) WHERE processed_at IS NULL;
CREATE INDEX learning_chat_operation ON app.learning_chat_outbox(user_id,(origin->>'operationId')) WHERE processed_at IS NULL;
CREATE TABLE app.learning_chat_turns (
  user_id uuid NOT NULL REFERENCES app.users(id) ON DELETE CASCADE,
  user_message_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  character_id uuid NOT NULL,
  cycle_id uuid NOT NULL,
  reply_event_id uuid NOT NULL DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,user_message_id),
  UNIQUE(user_id,reply_event_id)
);
CREATE TABLE app.learning_chat_operations (
  user_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  user_message_id uuid NOT NULL,
  request_fingerprint text NOT NULL,
  body_fingerprint text,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id,operation_id),
  FOREIGN KEY(user_id,user_message_id) REFERENCES app.learning_chat_turns(user_id,user_message_id) ON DELETE CASCADE
);
