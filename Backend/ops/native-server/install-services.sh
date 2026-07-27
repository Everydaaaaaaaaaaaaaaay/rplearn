#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "install-services.sh must run as root." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
environment_file="${1:-/opt/lingotrip/backend/.env.production}"

create_system_user() {
  local name="$1"
  local home="$2"
  if ! id "${name}" >/dev/null 2>&1; then
    useradd --system --home-dir "${home}" --create-home --shell /usr/sbin/nologin "${name}"
  fi
}

create_system_user lingotrip /var/lib/lingotrip
create_system_user caddy /var/lib/caddy
create_system_user minio /var/lib/lingotrip/minio
create_system_user mailpit /var/lib/lingotrip/mailpit

install -d -m 0755 -o root -g root /opt/lingotrip/releases /opt/lingotrip/dependencies
install -d -m 0755 -o root -g root /etc/caddy
install -d -m 0751 -o root -g lingotrip /var/lib/lingotrip
install -d -m 0750 -o redis -g redis /var/lib/lingotrip/redis
install -d -m 0750 -o minio -g minio /var/lib/lingotrip/minio
install -d -m 0750 -o mailpit -g mailpit /var/lib/lingotrip/mailpit
install -d -m 0750 -o caddy -g caddy /var/lib/caddy

for executable in \
  /opt/lingotrip/runtime/bin/node \
  /usr/bin/psql \
  /usr/bin/redis-server \
  /usr/local/bin/caddy \
  /usr/local/bin/mailpit \
  /usr/local/bin/minio
do
  if [[ ! -x "${executable}" ]]; then
    echo "Required executable is missing: ${executable}" >&2
    exit 1
  fi
done

"${script_dir}/render-environment.sh" "${environment_file}"
"${script_dir}/initialize-database.sh"
install -m 0644 "${script_dir}/Caddyfile" /etc/caddy/Caddyfile
systemctl disable --now \
  lingotrip-backup.timer \
  lingotrip-maintenance.timer 2>/dev/null || true
rm -f \
  /etc/systemd/system/lingotrip-backup.service \
  /etc/systemd/system/lingotrip-backup.timer \
  /etc/systemd/system/lingotrip-maintenance.service \
  /etc/systemd/system/lingotrip-maintenance.timer
install -m 0644 "${script_dir}"/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable \
  lingotrip-api.service \
  lingotrip-worker.service \
  lingotrip-redis.service \
  lingotrip-minio.service \
  lingotrip-mailpit.service \
  lingotrip-caddy.service
