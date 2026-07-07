#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Regenerate the Xcode project if project.yml changed (or the project doesn't exist yet).
if [ ! -d "LingoTrip.xcodeproj" ] || [ "project.yml" -nt "LingoTrip.xcodeproj" ]; then
  echo "Generating LingoTrip.xcodeproj via xcodegen..."
  xcodegen generate
fi

# Auto-pick the first available iPhone simulator (avoid hard-coding a device name that drifts).
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
  -quiet build
