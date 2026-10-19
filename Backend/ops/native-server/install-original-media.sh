#!/usr/bin/env bash
set -euo pipefail
[[ "${EUID}" = 0 ]] || exit 2
grep -qx '0::/system.slice/lingotrip-maintenance.service' /proc/self/cgroup || exit 2
exec /usr/bin/python3 "$(dirname "$0")/install-original-media.py" "$@"
