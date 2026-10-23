#!/usr/bin/env bash
set -euo pipefail
# One operation withdraws only the 2026-10-24 new namespace, with normal SSH auth.
batch="${1:-all}"
[[ "$#" -le 1 && "$batch" =~ ^(all|b[0-9]{3})$ ]] || { echo 'Use: withdraw-learning-expansion.sh [all|b000]' >&2; exit 2; }
exec ssh root@120.25.204.159 "/opt/lingotrip/ops/native-server/maintenance.sh expansion-withdraw ${batch}"
