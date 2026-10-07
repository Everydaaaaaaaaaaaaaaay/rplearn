#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 任务与观察均在受控单元内，终端断开不会解除资源限制。
"${script_dir}/resource-guard.py" check
"$@"
if [[ "$(basename "$1")" != deploy.sh ]]; then
  "${script_dir}/resource-guard.py" observe
fi
