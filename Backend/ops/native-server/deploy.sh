#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "deploy.sh must run as root." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
archive="${1:?Usage: deploy.sh RELEASE_ARCHIVE [VERSION]}"
version="${2:-$(tar -xOf "${archive}" ./RELEASE | tr -d '\r\n')}"
release_root="${RELEASE_ROOT:-/opt/lingotrip/releases}"
dependency_root="${DEPENDENCY_ROOT:-/opt/lingotrip/dependencies}"
runtime_node="${RUNTIME_NODE:-/opt/lingotrip/runtime/bin/node}"
runtime_corepack="${RUNTIME_COREPACK:-/opt/lingotrip/runtime/bin/corepack}"
release="${release_root}/${version}"
partial="${release}.partial"
lock_file="/run/lock/lingotrip-deploy.lock"
release_environment="/etc/lingotrip/release.env"
export PATH="/opt/lingotrip/runtime/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"

if [[ "${release_root}" != /opt/lingotrip/releases ]] ||
  [[ "${dependency_root}" != /opt/lingotrip/dependencies ]] ||
  [[ ! "${version}" =~ ^[a-zA-Z0-9._-]{4,64}$ ]]; then
  echo "Unsafe native deployment path or version." >&2
  exit 1
fi

exec 9>"${lock_file}"
if ! flock -n 9; then
  echo "Another LingoTrip deployment is already running." >&2
  exit 1
fi

[[ -x "${runtime_node}" ]] || {
  echo "Missing Node runtime: ${runtime_node}" >&2
  exit 1
}
[[ -f "${release_environment}" ]] || {
  echo "Missing release environment: ${release_environment}" >&2
  exit 1
}
[[ ! -e "${release}" ]] || {
  echo "Release already exists: ${release}" >&2
  exit 1
}

trap 'find "${partial}" -depth -delete 2>/dev/null || true' EXIT
install -d -m 0755 "${partial}"
tar -xzf "${archive}" -C "${partial}"
test "$(tr -d '\r\n' <"${partial}/RELEASE")" = "${version}"

dependency_key="$(
  {
    sha256sum "${partial}/package.json" | cut -d' ' -f1
    sha256sum "${partial}/pnpm-lock.yaml" | cut -d' ' -f1
  } |
    sha256sum |
    cut -d' ' -f1
)"
dependencies="${dependency_root}/${dependency_key}"
if [[ ! -d "${dependencies}/node_modules" ]]; then
  [[ -x "${runtime_corepack}" ]] || {
    echo "Missing Corepack for first-time dependency installation." >&2
    exit 1
  }
  dependency_partial="${dependencies}.partial"
  find "${dependency_partial}" -depth -delete 2>/dev/null || true
  install -d -m 0755 "${dependency_partial}"
  install -m 0644 \
    "${partial}/package.json" \
    "${partial}/pnpm-lock.yaml" \
    "${dependency_partial}/"
  (
    cd "${dependency_partial}"
    COREPACK_HOME=/opt/lingotrip/runtime/corepack \
      PNPM_HOME=/opt/lingotrip/runtime/pnpm \
      "${runtime_corepack}" pnpm install --frozen-lockfile --prod
  )
  mv "${dependency_partial}" "${dependencies}"
fi
ln -s "${dependencies}/node_modules" "${partial}/node_modules"
chown -R root:root "${partial}"
mv "${partial}" "${release}"

set -a
# Contains only URL-safe generated database credentials and PG variables.
source /etc/lingotrip/migration.env
set +a
(
  cd "${release}"
  "${runtime_node}" dist/cli/migrate.js
)
DATABASE_ADMIN_MODE=local-peer \
  "${script_dir}/apply-database-permissions.sh"

previous="$(readlink -f /opt/lingotrip/current 2>/dev/null || true)"
previous_version="$(sed -n 's/^APP_VERSION=//p' "${release_environment}" | tail -n 1)"
if [[ ! "${previous_version}" =~ ^[a-zA-Z0-9._-]{4,64}$ ]]; then
  echo "Unsafe current APP_VERSION in ${release_environment}." >&2
  exit 1
fi
rm -f /opt/lingotrip/current.next /opt/lingotrip/current.rollback
ln -s "${release}" /opt/lingotrip/current.next
mv -Tf /opt/lingotrip/current.next /opt/lingotrip/current

write_release_environment() {
  local release_version="$1"
  local environment_next
  environment_next="$(mktemp /etc/lingotrip/release.env.XXXXXX)"
  printf 'APP_VERSION=%s\n' "${release_version}" >"${environment_next}"
  chown root:lingotrip "${environment_next}"
  chmod 0640 "${environment_next}"
  mv -f "${environment_next}" "${release_environment}"
}

rollback() {
  write_release_environment "${previous_version}"
  if [[ -n "${previous}" && -d "${previous}" ]]; then
    ln -s "${previous}" /opt/lingotrip/current.rollback
    mv -Tf /opt/lingotrip/current.rollback /opt/lingotrip/current
    systemctl restart \
      lingotrip-api.service \
      lingotrip-worker.service \
      lingotrip-caddy.service || true
  else
    systemctl stop \
      lingotrip-api.service \
      lingotrip-worker.service \
      lingotrip-caddy.service || true
    rm -f /opt/lingotrip/current
  fi
}
trap rollback ERR

write_release_environment "${version}"
systemctl restart \
  lingotrip-api.service \
  lingotrip-worker.service \
  lingotrip-caddy.service
for _ in {1..30}; do
  if curl --fail --silent http://127.0.0.1:8080/health/ready >/dev/null; then
    trap - ERR
    find "${release_root}" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' |
      sort -nr |
      tail -n +6 |
      cut -d' ' -f2- |
      xargs --no-run-if-empty rm -r
    echo "Activated native release ${version}"
    exit 0
  fi
  sleep 1
done
echo "Native API did not become ready; rolling back." >&2
rollback
trap - ERR
exit 1
