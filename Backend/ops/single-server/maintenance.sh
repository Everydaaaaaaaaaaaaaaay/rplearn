#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${backend_dir}"

environment_file="${ENVIRONMENT_FILE:-.env.production}"
export ENVIRONMENT_FILE="${environment_file}"
docker compose \
  --env-file "${environment_file}" \
  -f compose.production.yml \
  run --rm maintenance
