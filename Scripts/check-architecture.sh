#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

scope="${1:---ios}"
if [[ "$#" -gt 1 ]] || [[ "$scope" != --ios && "$scope" != --backend && "$scope" != --all ]]; then
  echo 'Usage: Scripts/check-architecture.sh [--ios|--backend|--all] (default: --ios)' >&2
  exit 2
fi

failures=0

fail() {
  printf 'architecture check: %s\n' "$1" >&2
  failures=$((failures + 1))
}

root_names="$(git ls-files | awk -F/ 'NF > 1 { print $1 }' | sort -u)"
if printf '%s\n' "$root_names" | awk '{ key=tolower($0); count[key]++; names[key]=names[key] " " $0 } END { for (key in count) if (count[key] > 1) print names[key] }' | rg -q .; then
  fail 'top-level directory names differ only by case'
fi

if [[ "$scope" == --ios || "$scope" == --all ]]; then
  # Check the actual Feature boundary, not source length or documentation wording.
  feature_imports="$(rg -n '^[[:space:]]*(@[[:alnum:]_]+[[:space:]]+)*import[[:space:]]+((class|enum|func|let|protocol|struct|typealias|var)[[:space:]]+)?[[:alnum:]_]+Feature([[:space:].]|$)' \
    Packages/LingoKit/Sources/*Feature --glob '*.swift' || [[ "$?" == 1 ]])"
  if [[ -n "$feature_imports" ]]; then
    printf '%s\n' "$feature_imports" >&2
    fail 'Feature targets must not import other Feature targets'
  fi
  popup_overrides="$(rg -n 'DictExampleTranslationActions|exampleTranslationActions|allowsSystemTranslationFallback|dictionaryPopupServices\(' \
    Packages/LingoKit/Sources/*Feature --glob '*.swift' || [[ "$?" == 1 ]])"
  if [[ -n "$popup_overrides" ]]; then
    printf '%s\n' "$popup_overrides" >&2
    fail 'Feature screens must inherit dictionary popup services; do not forward or override example translation'
  fi
fi

if [[ "$scope" == --backend || "$scope" == --all ]]; then
  if [[ -x Backend/node_modules/.bin/depcruise ]]; then
    if ! (cd Backend && ./node_modules/.bin/depcruise --config dependency-cruiser.cjs src); then
      fail 'backend dependency boundaries failed'
    fi
  else
    fail 'dependency-cruiser unavailable; run pnpm install in Backend for backend checks'
  fi
fi

if ((failures > 0)); then
  exit 1
fi

printf 'architecture check (%s): ok\n' "$scope"
