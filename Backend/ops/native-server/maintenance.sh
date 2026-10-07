#!/usr/bin/env bash
set -euo pipefail
[[ "${EUID}" = 0 ]] || { echo '维护必须以 root 执行。' >&2; exit 1; }
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
action="${1:-}"
case "${action}" in
  deploy)
    [[ "$#" = 3 && "$3" =~ ^[a-zA-Z0-9._-]{4,64}$ ]] || exit 2
    command=("${script_dir}/deploy.sh" "$(realpath "$2")" "$3") ;;
  catalog-publish|bank-publish)
    [[ "$#" = 2 && "$2" =~ ^[a-f0-9]{64}$ ]] || exit 2
    name="${action%-publish}"
    command=(/opt/lingotrip/runtime/bin/node --max-old-space-size=128 --env-file=/etc/lingotrip/backend.env --env-file=/etc/lingotrip/release.env "dist/cli/learning-${name}.js" publish "$2") ;;
  catalog-validate|bank-validate|bank-pause)
    [[ "$#" = 1 ]] || exit 2
    name="${action%-*}"
    command=(/opt/lingotrip/runtime/bin/node --max-old-space-size=128 --env-file=/etc/lingotrip/backend.env --env-file=/etc/lingotrip/release.env "dist/cli/learning-${name}.js" "${action#*-}") ;;
  *) echo '用法：maintenance.sh deploy 归档 版本；catalog-publish/bank-publish 哈希；catalog-validate/bank-validate/bank-pause。' >&2; exit 2 ;;
esac

# 锁覆盖发布、目录导入与观察期；SSH 断开后固定单元名仍阻止重入。
exec 9>/run/lock/lingotrip-maintenance.lock
flock -n 9 || { echo '另一项维护尚未完成。' >&2; exit 1; }
if systemctl is-active --quiet lingotrip-maintenance.service; then
  echo '维护服务仍在运行，请查看日志，不要重复执行。' >&2
  exit 1
fi
[[ ! -e /run/lingotrip-release-transaction ]] || { echo '上次发布恢复尚未完成，已拒绝新维护。' >&2; exit 1; }
"${script_dir}/resource-guard.py" check
# 不放宽预算以绕过预检。需要更多内存的工作应拆分或离线完成。
systemd-run --wait --pipe --collect --unit=lingotrip-maintenance \
  -p WorkingDirectory=/opt/lingotrip/current \
  -p MemoryHigh=224M -p MemoryMax=256M -p MemorySwapMax=0 \
  -p CPUQuota=50% -p Nice=10 -p IOWeight=10 \
  -p 'IOReadBandwidthMax=/opt/lingotrip 2M' -p 'IOWriteBandwidthMax=/opt/lingotrip 2M' \
  -p RuntimeMaxSec=600 -p TimeoutStopSec=45 -p OOMPolicy=stop \
  -p "ExecStopPost=${script_dir}/recover-deployment.sh" \
  --setenv=DEPLOY_REQUIRE_CACHED_DEPENDENCIES=1 --setenv=DEPLOY_PRUNE_RELEASES=0 \
  --setenv=NODE_OPTIONS=--max-old-space-size=128 \
  "${script_dir}/maintenance-task.sh" "${command[@]}"
