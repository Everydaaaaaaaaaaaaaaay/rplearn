#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"

fixture="$(mktemp -d "$LINGOTRIP_REPO_ROOT/build/package-cache-test.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT
LINGOTRIP_SOURCE_PACKAGES_PATH="$fixture"
checkout="$fixture/checkouts/FluidAudio"
mkdir -p "$checkout"
printf '// fixture\n' > "$checkout/Package.swift"

if lingotrip_package_cache_ready; then
  echo 'FAIL: a manifest without Git objects must not count as a ready cache' >&2
  exit 1
fi

git -C "$checkout" init --quiet
git -C "$checkout" add Package.swift
git -C "$checkout" -c user.name='Package Cache Test' -c user.email='cache-test@example.invalid' commit --quiet -m fixture
lingotrip_package_cache_ready

# Only this disposable fixture is damaged to reproduce an interrupted package download.
commit="$(git -C "$checkout" rev-parse HEAD)"
rm "$checkout/.git/objects/${commit:0:2}/${commit:2}"
if lingotrip_package_cache_ready; then
  echo 'FAIL: a checkout with a missing HEAD object must not disable resolution' >&2
  exit 1
fi
echo 'Package cache readiness: 3 cases passed'
