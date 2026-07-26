#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "initialize-database.sh must run as root." >&2
  exit 1
fi

set -a
source /etc/lingotrip/migration.env
set +a

PGHOST=/var/run/postgresql \
PGUSER=postgres \
PGDATABASE=postgres \
runuser -u postgres -- psql \
  --dbname=postgres \
  --set=ON_ERROR_STOP=1 <<'SQL'
\getenv migrator_password PGPASSWORD

select format(
  'create role lingotrip_migrator login password %L nosuperuser createdb nocreaterole inherit noreplication nobypassrls',
  :'migrator_password'
)
where not exists (
  select 1
  from pg_roles
  where rolname = 'lingotrip_migrator'
)
\gexec

select format(
  'alter role lingotrip_migrator with login password %L nosuperuser createdb nocreaterole inherit noreplication nobypassrls',
  :'migrator_password'
)
\gexec

select 'create database lingotrip owner lingotrip_migrator'
where not exists (
  select 1
  from pg_database
  where datname = 'lingotrip'
)
\gexec

alter database lingotrip owner to lingotrip_migrator;
SQL
