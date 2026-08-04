#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 每次重新生成工程，确保新增源文件立即进入项目。
xcodegen generate --quiet

# 自动选择第一个可用的 iPhone 模拟器，避免设备名称变化导致脚本失效。
UDID=$(xcrun simctl list devices available \
  | grep -m 1 "iPhone" \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}')

if [ -z "${UDID:-}" ]; then
  echo "error: no available iPhone simulator found" >&2
  exit 1
fi

echo "Using simulator UDID: $UDID"

xcodebuild -project LingoTrip.xcodeproj \
  -scheme LingoTrip \
  -destination "platform=iOS Simulator,id=${UDID}" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGN_IDENTITY="-" \
  DEVELOPMENT_TEAM="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  -quiet build
