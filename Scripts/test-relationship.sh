#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace

udid="$(lingotrip_simulator_udid)"
passes="${RELATIONSHIP_TEST_PASSES:-2}"

if ! [[ "$passes" =~ ^[1-9][0-9]*$ ]]; then
  echo "错误：RELATIONSHIP_TEST_PASSES 必须是正整数" >&2
  exit 1
fi

echo "使用模拟器：$udid"
echo "关系专项稳定性轮数：$passes"

for ((pass = 1; pass <= passes; pass += 1)); do
  echo "关系专项回归 $pass/$passes"
  lingotrip_xcodebuild LingoTrip "$udid" \
    -only-testing:LingoTripTests/RelationshipServiceTests \
    -only-testing:LingoTripTests/RelationshipEngineStressTests \
    -only-testing:LingoTripTests/RelationshipMaturityTests \
    test
done

latest_result="$(find "$LINGOTRIP_DERIVED_DATA_PATH/Logs/Test" -maxdepth 1 -type d -name 'Test-LingoTrip-*.xcresult' -print0 | xargs -0 ls -td | head -1)"
echo "最终专项结果："
xcrun xcresulttool get test-results summary --path "$latest_result" --compact
