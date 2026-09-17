#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace
lingotrip_clear_shadowed_package_modules

udid="$(lingotrip_simulator_udid)"
echo "使用模拟器：$udid"

lingotrip_xcodebuild LingoTrip "$udid" "$@" test
