#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace

udid="$(lingotrip_simulator_udid)"
passes="${RELATIONSHIP_TEST_PASSES:-3}"

if ! [[ "$passes" =~ ^[1-9][0-9]*$ ]]; then
  echo "错误：RELATIONSHIP_TEST_PASSES 必须是正整数" >&2
  exit 1
fi

echo "使用模拟器：$udid"
echo "第三代关系科学性门禁轮数：$passes"

print_latest_result() {
  local label="${1:-当前专项结果}"
  local latest_result
  latest_result="$(find "$LINGOTRIP_DERIVED_DATA_PATH/Logs/Test" -maxdepth 1 -type d -name 'Test-LingoTrip-*.xcresult' -print0 | xargs -0 ls -td | head -1)"
  echo "${label}："
  xcrun xcresulttool get test-results summary --path "$latest_result" --compact
}

for ((pass = 1; pass <= passes; pass += 1)); do
  echo "关系专项回归 $pass/$passes"
  if ! lingotrip_xcodebuild LingoTrip "$udid" \
    -only-testing:LingoTripTests/RelationshipServiceTests \
    -only-testing:LingoTripTests/RelationshipEngineStressTests \
    -only-testing:LingoTripTests/RelationshipMaturityTests \
    -only-testing:LingoTripTests/RelationshipScientificValidationTests \
    test; then
    print_latest_result "失败专项结果"
    exit 1
  fi
  print_latest_result "第 $pass 轮结果"
done

print_latest_result "最终专项结果"
