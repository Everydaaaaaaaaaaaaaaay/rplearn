#!/usr/bin/env bash
set -euo pipefail
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
export LINGOTRIP_DERIVED_DATA_PATH="$fixture"
source "$(cd "$(dirname "$0")/.." && pwd)/lib/ios-worktree.sh"
products="$fixture/Build/Products/Debug-iphonesimulator"
framework="$products/PackageFrameworks/DomainKit.framework/Modules/DomainKit.swiftmodule"
mkdir -p "$framework" "$products/DomainKit.swiftmodule" "$products/Unrelated.swiftmodule"
touch "$framework/arm64-apple-ios-simulator.swiftmodule"
touch "$products/DomainKit.swiftmodule/arm64-apple-ios-simulator.swiftmodule"
touch "$products/Unrelated.swiftmodule/arm64-apple-ios-simulator.swiftmodule"
# Even equal/newer static mirrors can shadow a framework rebuilt later in this run.
lingotrip_clear_shadowed_package_modules
[[ ! -d "$products/DomainKit.swiftmodule" ]]
[[ -f "$framework/arm64-apple-ios-simulator.swiftmodule" ]]
[[ -d "$products/Unrelated.swiftmodule" ]]
lingotrip_clear_shadowed_package_modules
echo 'shadowed module regression: passed'
