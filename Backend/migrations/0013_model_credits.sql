create table app.credit_operations (
  user_id uuid not null references app.users(id) on delete cascade,
  operation_id uuid not null,
  parent_operation_id uuid,
  request_hash text not null,
  task text not null,
  plan text not null,
  window_key text not null,
  policy_version text not null,
  reserved_units numeric(24,0) not null check(reserved_units >= 0),
  settled_units numeric(24,0) check(settled_units >= 0),
  status text not null check(status in ('reserved','dispatched','pending','settled','released')),
  price jsonb not null,
  usage jsonb,
  provider_request_id text,
  result jsonb,
  reason text,
  reconciliation jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  dispatched_at timestamptz,
  completed_at timestamptz,
  primary key(user_id,operation_id)
);
--> statement-breakpoint
create index credit_operations_balance on app.credit_operations(user_id,window_key,status);
--> statement-breakpoint
create unique index credit_operations_one_repair on app.credit_operations(user_id,parent_operation_id) where parent_operation_id is not null;
--> statement-breakpoint
insert into app.service_metadata(key,value) values ('model-credits-v1',
 '{"version":"trial-2026-09-06","guest":"200000000","free":"100000000","pro":"400000000","max":"1200000000"}'::jsonb);

--> statement-breakpoint
create index credit_operations_recent on app.credit_operations(user_id,created_at desc);
--> statement-breakpoint
create index credit_operations_unresolved on app.credit_operations(user_id) where status in ('reserved','dispatched','pending') or (settled_units>reserved_units and reconciliation is null);
