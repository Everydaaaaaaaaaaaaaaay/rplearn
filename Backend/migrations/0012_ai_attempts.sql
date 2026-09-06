alter table app.ai_requests add column provider_attempts integer not null default 0;
--> statement-breakpoint
alter table app.usage_operations add column parent_operation_id uuid;
--> statement-breakpoint
create unique index usage_operations_one_repair on app.usage_operations(user_id,parent_operation_id) where parent_operation_id is not null;
