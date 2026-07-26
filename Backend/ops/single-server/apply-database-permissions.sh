#!/bin/sh
set -eu

: "${RUNTIME_DB_PASSWORD:?RUNTIME_DB_PASSWORD is required}"

psql \
  --set=ON_ERROR_STOP=1 \
  --set=runtime_password="${RUNTIME_DB_PASSWORD}" <<'SQL'
select format(
  'create role lingotrip_runtime login password %L nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls',
  :'runtime_password'
)
where not exists (
  select 1
  from pg_roles
  where rolname = 'lingotrip_runtime'
)
\gexec

select format(
  'alter role lingotrip_runtime with login password %L nosuperuser nocreatedb nocreaterole noinherit noreplication nobypassrls',
  :'runtime_password'
)
\gexec

revoke all on database lingotrip from lingotrip_runtime;
grant connect, temporary on database lingotrip to lingotrip_runtime;
revoke create on schema public from public;
revoke all on schema app, drizzle from lingotrip_runtime;
grant usage on schema app, drizzle to lingotrip_runtime;
grant select, insert, update, delete on all tables in schema app to lingotrip_runtime;
grant usage, select on all sequences in schema app to lingotrip_runtime;
grant select on all tables in schema drizzle to lingotrip_runtime;
alter default privileges for role lingotrip_migrator in schema app
  grant select, insert, update, delete on tables to lingotrip_runtime;
alter default privileges for role lingotrip_migrator in schema app
  grant usage, select on sequences to lingotrip_runtime;
alter role lingotrip_runtime set search_path to app, public;
SQL
