#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${backend_dir}"

environment_file="${ENVIRONMENT_FILE:-.env.production}"
if [[ ! -f "${environment_file}" ]]; then
  echo "Missing ${environment_file}; generate or provision it first." >&2
  exit 1
fi
chmod 600 "${environment_file}"
export ENVIRONMENT_FILE="${environment_file}"

compose=(docker compose --env-file "${environment_file}" -f compose.production.yml)

"${compose[@]}" config --quiet
"${compose[@]}" build api
"${compose[@]}" up -d --wait postgres redis minio mailpit
"${compose[@]}" run --rm minio-init
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm database-permissions
"${compose[@]}" up -d --remove-orphans api worker caddy
"${compose[@]}" up -d --wait api caddy

public_host="$(
  sed -n 's/^PUBLIC_HOST=//p' "${environment_file}" | tail -n 1
)"
if [[ -z "${public_host}" ]]; then
  echo "PUBLIC_HOST is missing from ${environment_file}" >&2
  exit 1
fi

curl \
  --fail \
  --retry 12 \
  --retry-all-errors \
  --retry-delay 5 \
  --silent \
  --show-error \
  "https://${public_host}/health/ready"
printf '\nDeployment completed for https://%s\n' "${public_host}"
