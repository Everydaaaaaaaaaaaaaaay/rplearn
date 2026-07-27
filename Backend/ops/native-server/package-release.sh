#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="${1:-$(git -C "${backend_dir}/.." rev-parse --short=12 HEAD)}"
output="${2:-${backend_dir}/build/lingotrip-backend-${version}.tar.gz}"
staging="$(mktemp -d)"
trap 'find "${staging}" -depth -delete' EXIT

cd "${backend_dir}"
pnpm build

install -d "${staging}/release"
cp -R dist migrations "${staging}/release/"
install -m 0644 package.json pnpm-lock.yaml "${staging}/release/"
printf '%s\n' "${version}" >"${staging}/release/RELEASE"

install -d "$(dirname "${output}")"
COPYFILE_DISABLE=1 tar -C "${staging}/release" -czf "${output}" .
echo "${output}"
