create table app.usage_operations (
  user_id uuid not null references app.users(id) on delete cascade,
  operation_id uuid not null,
  request_hash text not null,
  kind text not null check (kind in ('chat','advanced','auxiliary','voice')),
  window_key text not null,
  plan text not null,
  policy_version integer not null,
  amount integer not null check (amount > 0),
  settled_amount integer check (settled_amount >= 0 and settled_amount <= amount),
  status text not null check (status in ('reserved','succeeded','failed')),
  result jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  completed_at timestamptz,
  primary key (user_id, operation_id)
);
--> statement-breakpoint
create index usage_operations_balance on app.usage_operations(user_id, window_key, kind, status);
--> statement-breakpoint
alter table app.ai_requests add column operation_id uuid;
--> statement-breakpoint
alter table app.ai_requests add column cache_hit_tokens integer;
--> statement-breakpoint
alter table app.ai_requests add column cache_miss_tokens integer;
--> statement-breakpoint
