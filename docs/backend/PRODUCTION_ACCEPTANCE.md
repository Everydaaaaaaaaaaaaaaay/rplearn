# 商业发布验收与容量基线

## 使用边界

本文是发布证据清单，不是“部署到生产”的替代品。自动化能证明代码、镜像和本地依赖行为，
但不能替代目标云账号、Apple 沙盒/生产、SMTP 域名、DeepSeek 计费账号、备份恢复和真实告警
路由的验收。

所有负载与故障实验只允许在隔离预发布环境执行。环境使用独立数据库、Redis、对象桶、Apple
沙盒配置和限额明确的 AI key，不复制生产个人数据。执行前记录变更单、值班人、停止条件和
恢复负责人；生产禁止临时停止依赖来“验证”故障行为。

## 自动化发布门

每个候选 commit 必须有同一 CI run 的以下证据：

1. 格式、lint、类型、67+ 单元测试和 20+ PostgreSQL/Redis/MinIO 集成测试；
2. 编译后真实 API 的黑盒测试：注册、登录、refresh 轮换/重放、幂等资料、机票、同步；
3. OTLP 与日志隐私断言，以及真实进程优雅退出；
4. 最终 Distroless 镜像启动与 readiness 冒烟；
5. 仓库和镜像 Trivy high/critical/secret/IaC 零发现；
6. Distroless keyless 签名验证、生产依赖审计和镜像 CycloneDX SBOM；
7. 使用目标 Secret 执行迁移和 `production:check`，结果为 `passed=true`。

CI 证据必须绑定不可变 commit 和镜像 digest。重跑后只保留成功结果会掩盖抖动；发布记录同时
关联本次候选的全部失败和重跑原因。

## 容量测试

[`k6-capacity.js`](../../Backend/ops/load/k6-capacity.js) 使用固定到达率，混合读取
`/v1/me`、`/v1/sync/snapshot`、`/v1/billing/entitlements` 和 liveness。调用方通过
Secret 注入 `ACCESS_TOKENS_JSON`（短期 access token JSON 数组），脚本不会打印 token，
也不执行付费 AI 或写操作。

必需参数：

- `BASE_URL`：预发布 HTTPS API；
- `ACCESS_TOKENS_JSON`：至少一个测试账号的短期 access token；
- `STATE_RATE` / `PUBLIC_RATE`：每秒到达率；
- `DURATION`：k6 duration，例如 `15m`；
- `PREALLOCATED_VUS` / `MAX_VUS`：必须根据 runner 资源预留，出现 dropped iteration
  视为失败。

本地只验证脚本时可设置 `ALLOW_INSECURE_LOCAL=true`。正式基线分三轮：

| 轮次 | 负载              | 时长    | 目的                               |
| ---- | ----------------- | ------- | ---------------------------------- |
| 基线 | 预估峰值的 1.0 倍 | 15 分钟 | 验证 p95/p99、错误率和连接池稳态   |
| 峰值 | 预估峰值的 2.0 倍 | 15 分钟 | 验证自动扩容与无 dropped iteration |
| 浸泡 | 预估峰值的 0.7 倍 | 2 小时  | 查内存、连接、任务和缓存缓慢增长   |

脚本门槛与 SLO 对齐：普通权威读取 p95 < 750 ms，同步 p95 < 1 s，错误率 < 1%，liveness
p95 < 100 ms。通过还必须满足：API CPU 峰值低于 limit 的 70%、PostgreSQL 连接低于上限的
70%、Redis 无错误、事件循环无持续阻塞、内存浸泡末尾不持续上升。若达不到，不能只增加
`MAX_VUS` 或放宽阈值，需记录瓶颈、容量拐点、每副本安全 RPS 和扩容预算。

登录使用 Argon2，AI 和媒体直传具有完全不同的成本模型，不能用上述读取结果外推：

- 登录单独以测试账号池测量，限制会话增长并在结束后清理；
- AI 用受控 stub 做吞吐/超时测试，真实 DeepSeek 只做低频质量与计费用量 canary；
- 媒体对真实目标桶测量签名、PUT/GET 和 checksum，不把对象字节经过 API；
- Apple 通知使用官方沙盒/签名 fixture，不能用伪造生产交易压测。

## 受控故障演练

| 实验                        | 注入                          | 必须观察到                                                        | 恢复证据                           | 负责人         |
| --------------------------- | ----------------------------- | ----------------------------------------------------------------- | ---------------------------------- | -------------- |
| PostgreSQL 中断             | 预发布网络策略拒绝 API/worker | readiness 失败；权威写不接受；无本地兜底写                        | 连接恢复、迁移仍 current、快照一致 | SRE + Backend  |
| Redis 中断                  | 预发布网络策略拒绝 Redis      | readiness 失败；登录/注册/AI 限流 fail-closed；普通业务按文档降级 | 限流恢复且无原始 IP/email key      | SRE + Security |
| 对象桶中断                  | 拒绝 Head/PUT/GET/Delete      | readiness 失败；签名/完成拒绝；删除任务重试不丢失                 | pending/dead 收敛、桶仍私有        | SRE + Backend  |
| SMTP 4xx/5xx/超时           | 测试 SMTP 返回故障            | API 事务成功、加密 job 退避、最终 dead 告警                       | 恢复后同一 job 幂等成功            | Backend        |
| DeepSeek 429/超时/无效 JSON | 私有 stub 逐类响应            | 稳定错误、有限重试、配额不被绕过、无正文日志                      | canary 恢复、token 指标合理        | AI + Backend   |
| Apple 通知遗漏/乱序         | 沙盒 fixture 延迟和重放       | 事件幂等，旧事件不回退，对账最终收敛                              | entitlement 与 App Store 一致      | Billing        |
| Worker 强制终止             | 领取任务后终止 Pod            | 租约到期后重领，副作用不重复                                      | backlog 与 dead 告警清零           | SRE + Backend  |
| OTLP Collector 中断         | 拒绝 exporter                 | API 不阻塞，导出失败可见，业务日志仍脱敏                          | Collector 恢复且无队列失控         | SRE + Security |

每项至少保存：实验时间、候选 digest、注入方式、Prometheus/日志截图、数据库事实查询、恢复
时间和遗留项。任何跨账号读取、支付错误授权、数据丢失、Secret/PII 泄漏、无法恢复的任务
或超出既定停止条件，立即终止候选发布并进入事故流程。

## 外部商业验收

- Apple：Sandbox 购买、续订、宽限、退款、撤销、通知 V2、主动对账和账号删除撤销；
- DeepSeek：轮换后的专用 key、`deepseek-v4-flash` 目录可见、普通/SSE canary、限额和费用
  告警；
- 邮件：SPF、DKIM、DMARC、退信/投诉 webhook、验证/重置送达；
- 数据：托管 PostgreSQL PITR 隔离恢复、删除回执重放、对象版本/生命周期；
- 安全：域名 TLS、WAF/边缘限流、管理面私网隔离、运行时/迁移角色、Secret 轮换；
- 运营：11 条告警规则进入真实值班路由，runbook、状态页和事故角色完成演练；
- 客户端：当前 iOS Release 强制 HTTPS，TestFlight 对同一权威状态、订阅和 AI 网关验收。

最终 go/no-go 需要 Backend、iOS、SRE、Security/Privacy、Billing/Product 五方签字。每个未完成
项必须有明确阻断级别；账号接管、跨租户、订阅授权、恢复、删除、Secret 和 PII 项不存在
“上线后再补”的豁免。
