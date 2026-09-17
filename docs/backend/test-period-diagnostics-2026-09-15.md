# 测试期积分倍率与请求诊断（2026-09-15）

## 积分配置

负责人授权后，通过现有 `/internal/admin/ai/credit-rates` 管理接口将全局
`rateUnits` 从 5000（0.5 倍）改为 100（0.01 倍），配置版本从 2 变为 3。
无个人覆盖项；不修改余额和历史账单。沿用现有整数向上取整规则。
相对原配置，同等请求消耗约降至 1/50；极小用量仍受最小记账单位约束。

审计命令 ID：`eb7ef04d-c409-4486-92cd-0515b1856a74`。
恢复时先读取最新版本，再用新的幂等命令 ID 将全局 `rateUnits` 设回 5000；
不要复用旧命令或硬编码版本 3。尚未指定恢复日期，不设自动到期。

## 日志查询

服务器通过 systemd journal 保存 JSON 日志：

```sh
journalctl -u lingotrip-api --since '30 minutes ago' -o cat
journalctl -u lingotrip-worker --since '30 minutes ago' -o cat
```

- `http.request.finished`：路由模板、真实状态码、耗时、是否中断；超过 1000ms 标记 slow。
- `http.request.error`：公共错误码、状态码；用 requestId 与完成日志关联。
- `ai.completion.finished`：任务、AI 请求编号、操作编号、模型、Token 用量和耗时。
- `ai.stream.finished`：额外提供首个非空片段延迟、输出字符数、片段数、供应商请求编号，
  区分 completed / error / disconnected / incomplete。HTTP 200 不代表流式业务成功。
- 原有 worker 任务、数据库积分流水和审计设施继续使用。

新增日志不记录提示词、回复正文、认证头或密钥，也不逐 Token 输出日志。
首字延迟包含额度检查及供应商准备时间；Token 用量仅在供应商上报后存在。
HTTP 完成日志与 AI 业务完成日志分别描述网络响应与生成过程，按 requestId 关联。

## 验证与发布

定向测试覆盖状态码序列化、耗时与路由模板、正文/查询脱敏、SSE 成功及流内失败。
使用 Node 24 执行应用层测试和架构检查；类型检查、改动文件 ESLint 通过。
部署使用 `Backend/ops/native-server/package-release.sh` 和服务器现有原生发布脚本，
保留上一版本 `memory-budget-20260915` 供程序回滚；积分配置独立于程序版本。

发布结果：`diagnostics-20260915-01` 已激活（代码提交 `1ab1363`），API / worker 均 active。
线上 `/health/ready` 返回 ready；带诊断请求编号的健康请求记录状态 200、耗时，
未授权 AI 请求记录 UNAUTHORIZED / 401，并与完成日志关联；原完成日志状态码不再为 null。
发布后再次读取倍率：版本 3、rateUnits 100、个人覆盖为空。
AI 流式成功/失败日志由本地模拟供应商测试验证，本次未发起真实供应商付费生成。
