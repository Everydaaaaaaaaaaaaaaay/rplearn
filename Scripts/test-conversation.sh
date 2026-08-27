#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace skip

udid="$(lingotrip_simulator_udid)"
echo "运行轻量对话逻辑测试，使用模拟器：$udid"

lingotrip_xcodebuild LingoTripConversationTests "$udid" "$@" test
