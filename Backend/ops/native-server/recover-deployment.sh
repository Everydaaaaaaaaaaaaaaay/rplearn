#!/usr/bin/env bash
set -euo pipefail
state=/run/lingotrip-release-transaction
[[ -f "${state}" ]] || exit 0
{ IFS= read -r previous; IFS= read -r previous_version; IFS= read -r target; } < "${state}"
[[ "${previous}" =~ ^/opt/lingotrip/releases/[a-zA-Z0-9._-]{4,64}$ && -d "${previous}" && "${previous_version}" =~ ^[a-zA-Z0-9._-]{4,64}$ && "${target}" =~ ^/opt/lingotrip/releases/[a-zA-Z0-9._-]{4,64}$ ]] || { echo '回滚状态不完整，需要人工核查。' >&2; exit 1; }
current="$(readlink -f /opt/lingotrip/current)"
[[ "${current}" = "${target}" || "${current}" = "${previous}" ]] || { echo '当前版本已改变，拒绝覆盖其他发布。' >&2; exit 1; }
test "$(tr -d '\r\n' < "${previous}/RELEASE")" = "${previous_version}"
environment_next="$(mktemp /etc/lingotrip/release.env.XXXXXX)"
printf 'APP_VERSION=%s\n' "${previous_version}" > "${environment_next}"
chown root:lingotrip "${environment_next}"
chmod 0640 "${environment_next}"
mv -f "${environment_next}" /etc/lingotrip/release.env
ln -sfnT "${previous}" /opt/lingotrip/current.recover
mv -Tf /opt/lingotrip/current.recover /opt/lingotrip/current
# 启动由 systemd 执行，不把业务进程放入维护进程的内存配额。
systemctl restart --no-block lingotrip-api lingotrip-worker lingotrip-caddy
rm -f "${state}"
echo "发布未完成，已请求恢复 ${previous_version}；须继续确认公网健康。" >&2
