#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "bootstrap-ubuntu.sh must run as root." >&2
  exit 1
fi

node_version="24.18.0"
node_archive="node-v${node_version}-linux-x64.tar.xz"
node_base_url="https://nodejs.org/dist/v${node_version}"
caddy_version="2.10.2"
caddy_archive="caddy_${caddy_version}_linux_amd64.tar.gz"
caddy_sha512="747df7ee74de188485157a383633a1a963fd9233b71fbb4a69ddcbcc589ce4e2cc82dacf5dbbe136cb51d17e14c59daeb5d9bc92487610b0f3b93680b2646546"
caddy_binary_sha256="4ef1f68c70219536b2711fd16547a79841a2dec2d6b4e56b1e3e5e9da76028e6"
minio_release="RELEASE.2025-04-22T22-12-26Z"
minio_sha256="53e2a2cb16c5366ea6fbbc479c19ddb4c6a0948273e752f740fb1fbf27bb817c"
mailpit_version="1.27.11"
mailpit_archive="mailpit-linux-amd64.tar.gz"
mailpit_sha256="ba44986ae9801e6ba5f5f1a6947699b6e036bb36a55046941126602a8953af"
mailpit_binary_sha256="61f22a3943983ca20efc13e9e619646625e1c356b872d783a31163818244454d"
temporary="$(mktemp -d)"
trap 'find "${temporary}" -depth -delete' EXIT

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates \
  curl \
  gnupg \
  postgresql-common \
  redis-server \
  xz-utils

install -d -m 0755 /usr/share/postgresql-common/pgdg
curl --fail --silent --show-error \
  https://www.postgresql.org/media/keys/ACCC4CF8.asc |
  gpg --dearmor --yes --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg
printf '%s\n' \
  "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://mirrors.aliyun.com/postgresql/repos/apt noble-pgdg main" \
  >/etc/apt/sources.list.d/pgdg.list
apt-get update
apt-get install -y --no-install-recommends postgresql-17 postgresql-client-17

if [[ ! -x /opt/lingotrip/runtime/bin/node ]] ||
  [[ "$(/opt/lingotrip/runtime/bin/node --version)" != "v${node_version}" ]]; then
  curl --fail --silent --show-error \
    "${node_base_url}/SHASUMS256.txt" \
    --output "${temporary}/SHASUMS256.txt"
  curl --fail --silent --show-error \
    "${node_base_url}/${node_archive}" \
    --output "${temporary}/${node_archive}"
  (
    cd "${temporary}"
    grep " ${node_archive}\$" SHASUMS256.txt | sha256sum --check -
  )
  install -d -m 0755 /opt/lingotrip/runtime
  tar -xJf "${temporary}/${node_archive}" \
    --strip-components=1 \
    -C /opt/lingotrip/runtime
fi

if [[ ! -x /usr/local/bin/caddy ]] ||
  ! printf '%s  %s\n' "${caddy_binary_sha256}" /usr/local/bin/caddy |
    sha256sum --check --status; then
  curl --fail --location --silent --show-error \
    "https://github.com/caddyserver/caddy/releases/download/v${caddy_version}/${caddy_archive}" \
    --output "${temporary}/${caddy_archive}"
  printf '%s  %s\n' "${caddy_sha512}" "${temporary}/${caddy_archive}" |
    sha512sum --check -
  tar -xzf "${temporary}/${caddy_archive}" -C "${temporary}" caddy
  install -m 0755 "${temporary}/caddy" /usr/local/bin/caddy
fi

if [[ ! -x /usr/local/bin/minio ]] ||
  ! printf '%s  %s\n' "${minio_sha256}" /usr/local/bin/minio |
    sha256sum --check --status; then
  curl --fail --location --silent --show-error \
    "https://dl.min.io/server/minio/release/linux-amd64/archive/minio.${minio_release}" \
    --output "${temporary}/minio"
  printf '%s  %s\n' "${minio_sha256}" "${temporary}/minio" |
    sha256sum --check -
  install -m 0755 "${temporary}/minio" /usr/local/bin/minio
fi

if [[ ! -x /usr/local/bin/mailpit ]] ||
  ! printf '%s  %s\n' "${mailpit_binary_sha256}" /usr/local/bin/mailpit |
    sha256sum --check --status; then
  curl --fail --location --silent --show-error \
    "https://github.com/axllent/mailpit/releases/download/v${mailpit_version}/${mailpit_archive}" \
    --output "${temporary}/${mailpit_archive}"
  printf '%s  %s\n' "${mailpit_sha256}" "${temporary}/${mailpit_archive}" |
    sha256sum --check -
  tar -xzf "${temporary}/${mailpit_archive}" -C "${temporary}" mailpit
  install -m 0755 "${temporary}/mailpit" /usr/local/bin/mailpit
fi

systemctl disable --now redis-server.service
systemctl enable postgresql.service

/opt/lingotrip/runtime/bin/node --version
/usr/lib/postgresql/17/bin/postgres --version
/usr/bin/redis-server --version
/usr/local/bin/caddy version
/usr/local/bin/minio --version
/usr/local/bin/mailpit version --no-release-check
