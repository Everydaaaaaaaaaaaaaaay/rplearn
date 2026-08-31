#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scope="${1:-all}"

swift_root="$repo_root/Packages/LingoKit/Sources"
backend_root="$repo_root/Backend/src/modules"

print_swift_scope() {
  local module="$1"
  local module_dir="$swift_root/$module"
  if [[ ! -d "$module_dir" ]]; then
    echo "Unknown Swift target: $module" >&2
    return 1
  fi

  printf 'Swift target: %s\n' "$module"
  find "$module_dir" -type f -name '*.swift' -not -path '*/Resources/*' \
    | sed "s#^$repo_root/##" \
    | sort
  printf '\nPublic symbols\n'
  rg -n --glob '*.swift' --glob '!**/Resources/**' \
    '^(public |open )(final )?(actor|class|enum|protocol|struct|typealias|func|let|var) ' \
    "$module_dir" \
    | sed "s#^$repo_root/##" \
    || true
}

print_backend_scope() {
  local module="$1"
  local module_dir="$backend_root/$module"
  if [[ ! -d "$module_dir" ]]; then
    echo "Unknown backend module: $module" >&2
    return 1
  fi

  printf 'Backend module: %s\n' "$module"
  find "$module_dir" -type f -name '*.ts' \
    | sed "s#^$repo_root/##" \
    | sort
  printf '\nExports\n'
  rg -n --glob '*.ts' \
    '^export (async )?(abstract )?(class|const|enum|function|interface|type) ' \
    "$module_dir" \
    | sed "s#^$repo_root/##" \
    || true
}

case "$scope" in
  all)
    printf 'Repository entrypoints\n'
    printf '%s\n' \
      'App/LingoTripApp.swift' \
      'App/AppEnvironment.swift' \
      'App/RootView.swift' \
      'Packages/LingoKit/Package.swift' \
      'Backend/src/server.ts' \
      'Backend/src/worker.ts' \
      'Backend/src/db/schema.ts' \
      'Backend/src/db/user-schema.ts' \
      'project.yml'
    printf '\nSwift targets\n'
    find "$swift_root" -mindepth 1 -maxdepth 1 -type d -not -name '.*' \
      | sed 's#.*/##' \
      | sort
    printf '\nBackend modules\n'
    find "$backend_root" -mindepth 1 -maxdepth 1 -type d -not -name '.*' \
      | sed 's#.*/##' \
      | sort
    ;;
  backend:*)
    print_backend_scope "${scope#backend:}"
    ;;
  *)
    print_swift_scope "$scope"
    ;;
esac
