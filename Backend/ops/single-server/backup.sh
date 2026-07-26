#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${backend_dir}"

environment_file="${ENVIRONMENT_FILE:-.env.production}"
export ENVIRONMENT_FILE="${environment_file}"
backup_dir="${BACKUP_DIRECTORY:-/opt/lingotrip/backups}"
retention_days="${BACKUP_RETENTION_DAYS:-14}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="${backup_dir}/lingotrip-${timestamp}.dump"
temporary="${target}.partial"

install -d -m 700 "${backup_dir}"
trap 'rm -f "${temporary}"' EXIT

docker compose \
  --env-file "${environment_file}" \
  -f compose.production.yml \
  exec -T postgres \
  sh -ec 'PGPASSWORD="$POSTGRES_PASSWORD" pg_dump --format=custom --no-owner --no-acl --username="$POSTGRES_USER" "$POSTGRES_DB"' \
  >"${temporary}"

chmod 600 "${temporary}"
mv "${temporary}" "${target}"
find "${backup_dir}" -type f -name 'lingotrip-*.dump' -mtime "+${retention_days}" -delete
echo "Created ${target}"
