#!/usr/bin/env bash
set -euo pipefail

backend_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
version="${1:-$(git -C "${backend_dir}/.." rev-parse --short=12 HEAD)}"
output="${2:-${backend_dir}/build/lingotrip-backend-${version}.tar.gz}"
# 显式传入模板，保证临时打包文件落在调用者指定的磁盘。
staging="$(mktemp -d "${TMPDIR:-/tmp}/lingotrip-release.XXXXXX")"
trap 'find "${staging}" -depth -delete' EXIT

cd "${backend_dir}"
install -d "${staging}/release"
# A normal incremental build leaves emitted files for deleted sources behind in dist.
# Compile into this release's empty directory so reverted modules cannot be shipped.
pnpm exec tsc -p tsconfig.build.json --outDir "${staging}/release/dist"
cp -R migrations "${staging}/release/"
# 原创长音轨采用按SHA增量的独立资产包，避免在每次程序发布中复制全部语料。
tar --exclude='config/learning/originals/media' --exclude='config/learning/expansions/*/sources' -cf - config | tar -xf - -C "${staging}/release/"
install -m 0644 package.json pnpm-lock.yaml "${staging}/release/"
printf '%s\n' "${version}" >"${staging}/release/RELEASE"

install -d "$(dirname "${output}")"
# Python writes ordinary file members even when APFS stores the source sparsely.
# BSD tar may emit GNU.sparse metadata that the production GNU tar cannot extract.
# 作者草稿与 macOS 资源分叉不进入生产发布包。
python3 - "${staging}/release" "${output}" <<'PY'
import sys
import tarfile
from pathlib import Path

root, output = map(Path, sys.argv[1:])

def include(entry):
    if entry.name.startswith('./config/learning/authoring'):
        return None
    if any(part.startswith('._') or part == '.DS_Store' for part in Path(entry.name).parts):
        return None
    return entry

with tarfile.open(output, 'w:gz', format=tarfile.PAX_FORMAT) as archive:
    archive.add(root, arcname='.', filter=include)
PY
echo "${output}"
