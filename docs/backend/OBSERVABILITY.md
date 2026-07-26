# LingoTrip 可观测性与 SLO

## 原则

- PostgreSQL 保存业务事实，Prometheus 指标用于趋势、告警和快速定位，二者不能互相替代；
- 指标标签只使用路由模板、状态族、任务类型、环境和有限枚举，不使用用户、设备、交易、对象或请求 ID；
- 应用日志是结构化 JSON，以 `requestId` 关联一次请求；不记录 AI 正文、语音、Token、收据或管理凭据；
- `/health/live` 只说明进程可响应，`/health/ready` 才检查 PostgreSQL、Redis 和启用后的对象存储；
- `/internal/metrics` 必须由独立长随机令牌保护，并只能从监控网络访问。

## 服务级目标

首个商业版本采用以下 30 天滚动目标：

| 用户路径                 | SLI                                              | SLO    |
| ------------------------ | ------------------------------------------------ | ------ |
| 公网 API 可用性          | 非内部请求中非 5xx 的比例                        | 99.9%  |
| 登录、状态读取与普通写入 | 成功请求 p95                                     | 750 ms |
| 增量同步                 | 成功请求 p95                                     | 1 s    |
| AI 请求受理              | 非客户端拒绝请求中能得到成功或明确上游失败的比例 | 99.0%  |
| 商店通知处理             | 已验签通知进入最终处理状态的时间 p95             | 5 min  |
| 主动订阅对账             | 到期任务开始处理的延迟                           | 30 min |
| 后台任务                 | 普通任务进入成功或确定死信状态的时间 p95         | 5 min  |

99.9% 的 30 天可用性目标对应约 43.2 分钟错误预算。快速和慢速燃烧率告警同时看短、长窗口，避免短暂噪声，也避免缓慢故障耗尽整月预算。

## 指标面

HTTP 指标：

- `lingotrip_http_requests_total`
- `lingotrip_http_request_duration_seconds`
- `lingotrip_http_active_requests`

跨进程运营事实由 API 实例从数据库按最多每 10 秒一次的频率刷新：

- `lingotrip_jobs` 与 `lingotrip_job_oldest_pending_age_seconds`
- `lingotrip_subscriptions`
- `lingotrip_billing_reconciliation_overdue`
- `lingotrip_billing_event_backlog` 与 `lingotrip_billing_event_oldest_age_seconds`
- `lingotrip_ai_requests_5m` 与 `lingotrip_ai_tokens_5m`
- `lingotrip_operational_metrics_collection_success`
- `lingotrip_operational_metrics_collection_timestamp_seconds`

刷新失败不会让 Prometheus 抓取端点失效：端点继续返回上次成功快照，同时将成功标志设为 `0`。这样数据库故障不会被误判成监控目标消失。

## 告警部署

将 [`prometheus-rules.yml`](../../Backend/ops/monitoring/prometheus-rules.yml) 交给 Prometheus 或兼容的托管监控服务加载，并让发布流水线使用 `promtool check rules` 校验最终渲染文件。仓库迁移或改名时同步更新规则中的 `runbook_url`。

告警路由至少区分：

- `critical`：立即通知当班人员，并在 5 分钟内确认；
- `warning`：工作时间处理，持续恶化或同时影响 SLO 时升级；
- 账单、账号接管和数据隔离事件，无论当前请求量大小都按 `critical` 处理。

## 仪表盘最低内容

单一服务总览应同时显示：

1. 请求量、5xx 比例、p50/p95/p99 延迟和活跃连接；
2. PostgreSQL、Redis、对象存储 readiness；
3. 待处理、运行中、死信任务及最老等待时间；
4. 订阅状态分布、通知积压和主动对账滞后；
5. AI 五分钟成功率、任务分布、输入/输出 token 量；
6. 进程 CPU、内存、事件循环延迟、GC 和重启次数；
7. 当前版本、部署时间与最近变更链接。

仪表盘不展示邮箱、Apple transaction ID、AI 文本、语音路径或任何可还原单个用户的标签。

## 保留与访问

- Prometheus 原始高分辨率数据保留 30 天，长期聚合数据按业务需要保留 13 个月；
- 应用日志热存储建议 30 天，审计表按 `AUDIT_RETENTION_DAYS` 的治理策略归档或清理；
- 生产日志、指标和审计后台使用不同角色，默认只读，并记录管理员访问；
- 排障导出在工单结束后删除，禁止把生产遥测复制到个人长期存储。
