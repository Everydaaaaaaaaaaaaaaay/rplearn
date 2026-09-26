-- 删除授权仅覆盖旧学习：普通文本消息保留，移除其附加小测字段。
DELETE FROM app.sync_changes
WHERE payload->>'resourceType'='quiz_record'
   OR (payload->>'resourceType'='message' AND payload->'payload'->>'kind'='quiz');
DELETE FROM app.command_receipts
WHERE response->>'resourceType'='quiz_record'
   OR (response->>'resourceType'='message' AND response->'payload'->>'kind'='quiz');
DELETE FROM app.content_records
WHERE resource_type='quiz_record'
   OR (resource_type='message' AND payload->>'kind'='quiz');
UPDATE app.content_records SET payload=payload-'quizJson'-'quizChosenIndex'
WHERE resource_type='message' AND (payload ? 'quizJson' OR payload ? 'quizChosenIndex');
UPDATE app.content_records SET payload=payload-'quizOptOut'-'turnsSinceQuiz'
WHERE resource_type='conversation' AND (payload ? 'quizOptOut' OR payload ? 'turnsSinceQuiz');
UPDATE app.sync_changes SET payload=payload #- '{payload,quizJson}' #- '{payload,quizChosenIndex}'
WHERE payload->>'resourceType'='message';
UPDATE app.sync_changes SET payload=payload #- '{payload,quizOptOut}' #- '{payload,turnsSinceQuiz}'
WHERE payload->>'resourceType'='conversation';
UPDATE app.command_receipts SET response=response #- '{payload,quizJson}' #- '{payload,quizChosenIndex}'
WHERE response->>'resourceType'='message';
UPDATE app.command_receipts SET response=response #- '{payload,quizOptOut}' #- '{payload,turnsSinceQuiz}'
WHERE response->>'resourceType'='conversation';
--> statement-breakpoint
ALTER TABLE app.user_profiles DROP COLUMN quiz_globally_enabled;
UPDATE app.ai_routes SET enabled=false,config_version=config_version+1,updated_at=now()
WHERE task='quiz';
