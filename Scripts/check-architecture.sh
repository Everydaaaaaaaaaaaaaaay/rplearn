#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

failures=0

fail() {
  printf 'architecture check: %s\n' "$1" >&2
  failures=$((failures + 1))
}

root_names="$(git ls-files | awk -F/ 'NF > 1 { print $1 }' | sort -u)"
if printf '%s\n' "$root_names" | awk '{ key=tolower($0); count[key]++; names[key]=names[key] " " $0 } END { for (key in count) if (count[key] > 1) print names[key] }' | rg -q .; then
  fail 'top-level directory names differ only by case'
fi

if git ls-files | rg -q '(^|/)(WT|wt)[A-Za-z0-9_-]*\.(swift|ts|tsx|js|mjs|py)$'; then
  fail 'source filename contains a temporary worktree identifier'
fi

target_count="$(find Packages/LingoKit/Sources -mindepth 1 -maxdepth 1 -type d -not -name '.*' | wc -l | tr -d ' ')"
if ! rg -q "${target_count} 个 Target" docs/architecture.md; then
  fail "docs/architecture.md does not report the current $target_count Swift targets"
fi

oversized="$({
  find App Packages/LingoKit/Sources -type f -name '*.swift' -not -path '*/Resources/*' -print0
  find Backend/src -type f -name '*.ts' -print0
} | xargs -0 wc -l | awk '$2 != "total" && $1 > 800 { print $1, $2 }')"
if [[ -n "$oversized" ]]; then
  printf '%s\n' "$oversized" >&2
  fail 'production source files exceed the 800-line review ceiling'
fi

if [[ -x Backend/node_modules/.bin/depcruise ]]; then
  if ! (cd Backend && pnpm exec depcruise --config dependency-cruiser.cjs src); then
    fail 'backend dependency boundaries failed'
  fi
else
  fail 'dependency-cruiser unavailable; run pnpm install in Backend'
fi

if ((failures > 0)); then
  exit 1
fi

printf 'architecture check: ok\n'
