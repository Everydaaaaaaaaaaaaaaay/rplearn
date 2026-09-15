# 管理后台报错与日志

入口：现有 `/internal/admin/ai` 控制台的「报错与日志」。沿用管理员 Token 鉴权。

可按近 1 / 6 / 24 / 72 小时、API / worker、日志级别、错误码、请求 / AI / 操作 / 后台任务编号精确筛选。
点击错误聚合可筛选错误码；日志详情的「查看关联日志」清除级别和错误码限制，查询同一编号的记录。

统计为当前筛选内的日志统计：同一 requestId 的多条失败合并计数，无请求编号的独立错误事件逐条计数。
HTTP 4xx 计入失败；服务端错误为 HTTP 5xx 或 error 级别；AI 流内失败和客户端中断分别展示。
此处不是无限期、全量业务账本；顶部用户成本筛选不影响日志分区。

## 读取与权限

接口 `GET /internal/admin/diagnostics` 仅管理员可用，返回 `Cache-Control: no-store`。
异步执行固定 `journalctl` 命令，仅查询 `lingotrip-api.service` 和 `lingotrip-worker.service`。
无 shell 拼接，不接受用户指定命令、路径或服务名；超时 8 秒、输出上限 32 MiB。
每个时间窗口缓存 10 秒并合并并发读取；最多读取最近 20,000 条，超限明确提示缩小范围。
日志保留期沿用服务器 journal 配置，服务重启后仍可查看保留日志。

API 服务通过 `SupplementaryGroups=systemd-journal` 获得日志只读权限。
此 Linux 组可读取系统 journal，因此仅给 API 服务进程增加补充组，不修改登录用户组；
查询接口固定限定上述两个服务，并仅向浏览器返回白名单诊断字段。
生产以 `/etc/systemd/system/lingotrip-api.service.d/diagnostics.conf` 配置该项，
与仓库 systemd 模板保持一致。添加后执行 `systemctl daemon-reload`，随发布重启 API。

不展示原始 MESSAGE、提示词、回复正文、请求头、异常原文、凭证或未经筛选的堆栈。
未知旧日志显示 service.log；已有字段仍可用于关联。worker 错误补充安全异常类型，便于区分超时等原因。
日志无权限、超时或读取异常返回 503，界面显示不可用，不伪装成零报错。

## 验证

定向测试覆盖鉴权、非法筛选、脱敏、错误去重、流内失败、分页、关联编号、截断和读取失败。
浏览器使用本地模拟日志验证统计、详情及关联筛选；线上发布后检查真实 journal 数据及权限。
回滚程序使用上一发布目录；如撤销该能力，可同时移除上述独立 drop-in 后重载并重启 API。
