#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

passes="${RELATIONSHIP_TEST_PASSES:-1}"

if ! [[ "$passes" =~ ^[1-9][0-9]*$ ]]; then
  echo "错误：RELATIONSHIP_TEST_PASSES 必须是正整数" >&2
  exit 1
fi

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace
udid="$(lingotrip_simulator_udid)"

echo "使用模拟器：$udid"
echo "关系专项回归轮数：${passes}（排查不稳定问题时可显式增加）"

print_result() {
  local result="$1"
  local label="$2"
  echo "${label}："
  if [[ -d "$result" ]]; then
    xcrun xcresulttool get test-results summary --path "$result" --compact
  else
    echo "本轮尚未产生测试结果，请查看上方构建错误。" >&2
  fi
}

for ((pass = 1; pass <= passes; pass += 1)); do
  echo "关系专项回归 $pass/$passes"
  result="$LINGOTRIP_DERIVED_DATA_PATH/Logs/Test/Relationship-$(date +%Y%m%d-%H%M%S)-$$-$pass.xcresult"
  if ! lingotrip_xcodebuild LingoTrip "$udid" \
    -resultBundlePath "$result" \
    -only-testing:LingoTripTests/RelationshipServiceTests \
    -only-testing:LingoTripTests/RelationshipEngineStressTests \
    -only-testing:LingoTripTests/RelationshipMaturityTests \
    -only-testing:LingoTripTests/RelationshipScientificValidationTests \
    "$@" test; then
    print_result "$result" "失败专项结果"
    exit 1
  fi
  print_result "$result" "第 $pass 轮结果"
done
