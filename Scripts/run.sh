#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

lingotrip_acquire_pipeline_lock
lingotrip_prepare_workspace

udid="$(lingotrip_simulator_udid)"
echo "构建并安装到模拟器：$udid"
lingotrip_boot_simulator "$udid"
lingotrip_xcodebuild LingoTrip "$udid" "$@" build

app_path="$LINGOTRIP_DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/LingoTrip.app"
if [[ ! -d "$app_path" ]]; then
  echo "错误：未找到构建产物：$app_path" >&2
  exit 1
fi

bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Info.plist")"
xcrun simctl install "$udid" "$app_path"
xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"

echo "已安装并启动：$bundle_id"
