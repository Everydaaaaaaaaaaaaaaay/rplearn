-- 不修改难度枚举、历史挑战或已有积分；首次读取默认通用英语。
CREATE TABLE app.learning_preferences (
  user_id uuid PRIMARY KEY REFERENCES app.users(id) ON DELETE CASCADE,
  direction text NOT NULL CHECK (direction IN (
    'general', 'entrance-english-1', 'entrance-english-2', 'toefl-ibt-2026', 'ielts-academic'
  )),
  revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  updated_at timestamptz NOT NULL DEFAULT now()
);
