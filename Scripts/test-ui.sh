#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"
lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace
lingotrip_clear_shadowed_package_modules
udid="$(lingotrip_simulator_udid)"
echo "运行 UI 路径测试，使用模拟器：$udid"

# 单条测试默认 300 秒超时即判失败，避免模拟器异常时整批挂起；
# 长流程用 LINGOTRIP_UI_TEST_TIMEOUT 放宽，显式传入 -test-timeouts-enabled 时以调用方为准。
timeout_arguments=()
if [[ " $* " != *" -test-timeouts-enabled "* ]]; then
  timeout_arguments=(
    -test-timeouts-enabled YES
    -default-test-execution-time-allowance "${LINGOTRIP_UI_TEST_TIMEOUT:-300}"
  )
fi
lingotrip_xcodebuild LingoTripPerformanceTests "$udid" ${timeout_arguments[@]+"${timeout_arguments[@]}"} "$@" test
