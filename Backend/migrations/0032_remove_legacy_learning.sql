-- 用户明确授权删除未发布的旧学习记录；不触及聊天、档案、收藏或剧情数据。
DROP TABLE app.learning_states;
DROP TABLE app.unit_learning_attempts;
DROP TABLE app.unit_learning_templates;
DROP TABLE app.unit_learning_accounts;
DROP TABLE app.unit_learning_characters;
DROP TABLE app.unit_learning_messages;
--> statement-breakpoint
-- 保留供应商调用与计费审计，旧学习路由退出运行。
UPDATE app.ai_routes SET enabled=false,config_version=config_version+1,updated_at=now()
WHERE task IN ('learning_review','unit_authoring');
