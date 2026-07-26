# LingoTrip 可观测性与 SLO

## 原则

- PostgreSQL 保存业务事实，Prometheus 指标用于趋势、告警和快速定位，二者不能互相替代；
- 指标标签只使用路由模板、状态族、任务类型、环境和有限枚举，不使用用户、设备、交易、对象或请求 ID；
- 应用日志是结构化 JSON，以 `requestId` 关联一次请求；不记录 AI 正文、语音、Token、收据或管理凭据；
- 启用 OpenTelemetry 后，日志自动增加 `traceId`/`spanId`；span URL 会移除 query 并把动态路径段归一化为 `:id`；
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

## 分布式追踪

追踪默认关闭。生产通过 Secret/配置注入以下变量后启用：

```text
OTEL_TRACING_ENABLED=true
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=https://collector.example/v1/traces
OTEL_EXPORTER_OTLP_TRACES_TIMEOUT=3000
OTEL_TRACE_SAMPLE_RATIO=0.1
OTEL_SERVICE_NAME=lingotrip-api
APP_VERSION=<immutable release id>
```

Worker 使用同一镜像时设置 `OTEL_SERVICE_NAME=lingotrip-worker`。未显式设置服务名时，启动器会根据 API/Worker 入口自动区分。OTLP 鉴权头使用标准 `OTEL_EXPORTER_OTLP_HEADERS` 注入，它属于 Secret，不写入仓库或日志。

采样器对根请求按 trace ID 做稳定比例采样，对来自公网的 `traceparent` 仍重新应用本服务比例，避免客户端强制采样耗尽额度；本地子 span 保持父级决定。健康检查和 metrics 抓取不生成 span。

HTTP/Fastify 与基于 Undici 的上游调用自动建立 span，并传播 W3C 上下文。为了隐私和低基数：

- 不采集请求/响应 body、Cookie、Authorization 或自定义业务 header；
- 所有 query 值都从 span URL 中移除；
- UUID、数字交易 ID、对象 key 等动态路径段统一记录为 `:id`；
- 上游 span 只在已有父 span 时创建；
- Worker 为每个已领取任务建立 `job.process` 根 span，只记录有限任务类型、尝试次数与稳定结果，不记录 job/user/object ID 或加密 payload；
- OTLP Collector 置于私网，生产使用 TLS，并在 Collector 侧执行保留、访问控制和二次过滤。

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
