#!/usr/bin/env bash
set -euo pipefail

backup_dir="${BACKUP_DIRECTORY:-/opt/lingotrip/backups}"
retention_days="${BACKUP_RETENTION_DAYS:-14}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
target="${backup_dir}/lingotrip-${timestamp}"
partial="${target}.partial"

set -a
source /etc/lingotrip/migration.env
set +a
install -d -m 0700 "${backup_dir}"
install -d -m 0700 "${partial}"
trap 'find "${partial}" -depth -delete 2>/dev/null || true' EXIT

pg_dump \
  --format=custom \
  --no-owner \
  --no-acl \
  --file="${partial}/postgres.dump" \
  lingotrip
tar -C /var/lib/lingotrip -czf "${partial}/minio.tar.gz" minio
chmod 0600 "${partial}/postgres.dump" "${partial}/minio.tar.gz"
mv "${partial}" "${target}"
find "${backup_dir}" -mindepth 1 -maxdepth 1 -type d -name 'lingotrip-*' \
  -mtime "+${retention_days}" -exec rm -r -- {} +
echo "Created ${target}"
