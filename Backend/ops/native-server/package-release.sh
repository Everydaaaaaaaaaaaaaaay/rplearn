#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="${1:-$(git -C "${backend_dir}/.." rev-parse --short=12 HEAD)}"
output="${2:-${backend_dir}/build/lingotrip-backend-${version}.tar.gz}"
staging="$(mktemp -d)"
trap 'find "${staging}" -depth -delete' EXIT

cd "${backend_dir}"
install -d "${staging}/release"
# A normal incremental build leaves emitted files for deleted sources behind in dist.
# Compile into this release's empty directory so reverted modules cannot be shipped.
pnpm exec tsc -p tsconfig.build.json --outDir "${staging}/release/dist"
cp -R migrations config "${staging}/release/"
install -m 0644 package.json pnpm-lock.yaml "${staging}/release/"
printf '%s\n' "${version}" >"${staging}/release/RELEASE"

install -d "$(dirname "${output}")"
COPYFILE_DISABLE=1 tar --no-xattrs -C "${staging}/release" -czf "${output}" .
echo "${output}"
