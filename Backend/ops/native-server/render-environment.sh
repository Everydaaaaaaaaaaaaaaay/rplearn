#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "render-environment.sh must run as root." >&2
  exit 1
fi

source_file="${1:-/opt/lingotrip/backend/.env.production}"
target_dir="${LINGOTRIP_CONFIG_DIRECTORY:-/etc/lingotrip}"
if [[ ! -f "${source_file}" ]]; then
  echo "Missing production environment file: ${source_file}" >&2
  exit 1
fi

value_for() {
  local key="$1"
  local value
  value="$(sed -n "s/^${key}=//p" "${source_file}" | tail -n 1)"
  if [[ -z "${value}" ]]; then
    echo "Missing ${key} in ${source_file}" >&2
    exit 1
  fi
  printf '%s' "${value}"
}

postgres_password="$(value_for POSTGRES_PASSWORD)"
runtime_password="$(value_for RUNTIME_DB_PASSWORD)"
redis_password="$(value_for REDIS_PASSWORD)"
public_host="$(value_for PUBLIC_HOST)"
media_bucket="$(value_for MEDIA_S3_BUCKET)"
media_access_key="$(value_for MEDIA_S3_ACCESS_KEY_ID)"
media_secret_key="$(value_for MEDIA_S3_SECRET_ACCESS_KEY)"

for password in "${postgres_password}" "${runtime_password}" "${redis_password}"; do
  if [[ ! "${password}" =~ ^[a-zA-Z0-9._~-]{32,}$ ]]; then
    echo "Native service passwords must be URL-safe and at least 32 characters." >&2
    exit 1
  fi
done

install -d -m 0751 -o root -g lingotrip "${target_dir}"
umask 077
runtime_file="$(mktemp)"
migration_file="$(mktemp)"
minio_file="$(mktemp)"
caddy_file="$(mktemp)"
redis_file="$(mktemp)"
release_file="$(mktemp)"
trap 'rm -f "${runtime_file}" "${migration_file}" "${minio_file}" "${caddy_file}" "${redis_file}" "${release_file}"' EXIT

while IFS= read -r line; do
  [[ "${line}" =~ ^[A-Z][A-Z0-9_]*= ]] || continue
  key="${line%%=*}"
  case "${key}" in
    APP_VERSION | DATABASE_URL | DISTROLESS_REGISTRY | HOST | MIGRATION_DATABASE_URL | \
      NODE_ENV | PORT | POSTGRES_PASSWORD | PUBLIC_HOST | REDIS_PASSWORD | REDIS_URL | \
      RUNTIME_DB_PASSWORD | SMTP_HOST | SMTP_PORT)
      continue
      ;;
  esac
  printf '%s\n' "${line}" >>"${runtime_file}"
done <"${source_file}"

cat >>"${runtime_file}" <<EOF
DATABASE_URL=postgres://lingotrip_runtime:${runtime_password}@127.0.0.1:5432/lingotrip
HOST=127.0.0.1
NODE_ENV=production
PORT=8080
REDIS_URL=redis://:${redis_password}@127.0.0.1:6379/0
SMTP_HOST=127.0.0.1
SMTP_PORT=1025
EOF

cat >"${migration_file}" <<EOF
MIGRATION_DATABASE_URL=postgres://lingotrip_migrator:${postgres_password}@127.0.0.1:5432/lingotrip
NODE_ENV=production
PGDATABASE=lingotrip
PGHOST=127.0.0.1
PGPASSWORD=${postgres_password}
PGPORT=5432
PGUSER=lingotrip_migrator
RUNTIME_DB_PASSWORD=${runtime_password}
EOF

cat >"${minio_file}" <<EOF
MINIO_ROOT_PASSWORD=${media_secret_key}
MINIO_ROOT_USER=${media_access_key}
EOF

cat >"${caddy_file}" <<EOF
MEDIA_S3_BUCKET=${media_bucket}
PUBLIC_HOST=${public_host}
EOF

cat >"${redis_file}" <<EOF
bind 127.0.0.1 -::1
protected-mode yes
port 6379
supervised systemd
daemonize no
dir /var/lib/lingotrip/redis
appendonly yes
appendfsync everysec
save 900 1
requirepass ${redis_password}
loglevel notice
EOF

install -m 0640 -o root -g lingotrip "${runtime_file}" "${target_dir}/backend.env"
install -m 0600 -o root -g root "${migration_file}" "${target_dir}/migration.env"
install -m 0600 -o root -g root "${minio_file}" "${target_dir}/minio.env"
install -m 0640 -o root -g caddy "${caddy_file}" "${target_dir}/caddy.env"
install -m 0640 -o root -g redis "${redis_file}" "${target_dir}/redis.conf"
if [[ ! -e "${target_dir}/release.env" ]]; then
  printf 'APP_VERSION=%s\n' "$(value_for APP_VERSION)" >"${release_file}"
  install -m 0640 -o root -g lingotrip "${release_file}" "${target_dir}/release.env"
fi
