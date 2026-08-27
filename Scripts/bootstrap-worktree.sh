#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_prepare_workspace

echo "工作树已准备完成"
echo "独立 DerivedData：$LINGOTRIP_DERIVED_DATA_PATH"
echo "共享依赖缓存：$LINGOTRIP_SOURCE_PACKAGES_PATH"
