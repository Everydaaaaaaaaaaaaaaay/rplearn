#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 同一正式 Bundle ID 下，每次上传必须使用更大的 Build Number。
# 项目约定一个逻辑工作一个提交，因此提交总数可作为稳定、自动递增的默认值。
lingotrip_marketing_version="${LINGOTRIP_MARKETING_VERSION:-1.0}"
lingotrip_build_number="${LINGOTRIP_BUILD_NUMBER:-$(git rev-list --count HEAD)}"

if [[ ! "$lingotrip_build_number" =~ ^[1-9][0-9]*$ ]]; then
  echo "错误：LINGOTRIP_BUILD_NUMBER 必须是正整数" >&2
  exit 1
fi

xcodegen generate --quiet

echo "正在归档 LingoTrip ${lingotrip_marketing_version} (${lingotrip_build_number})"

xcodebuild archive \
  -project LingoTrip.xcodeproj \
  -scheme LingoTrip \
  -configuration Release \
  -destination "generic/platform=iOS" \
  MARKETING_VERSION="$lingotrip_marketing_version" \
  CURRENT_PROJECT_VERSION="$lingotrip_build_number"

echo "归档完成，可在 Xcode Organizer 中继续分发到 App Store Connect。"
