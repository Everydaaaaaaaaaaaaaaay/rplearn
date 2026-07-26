# 运行与事故手册

## SLO 与告警

建议初始 SLO：

- 月度 API 可用性 99.9%；
- 非 AI API P95 小于 400ms，P99 小于 1s；
- AI 首 token P95 小于 4s，完整请求按任务单独观测；
- 计费通知 99% 在 60 秒内处理；
- 审计写入失败为零容忍告警。

必须告警：

- 5xx 比例 5 分钟超过 2%，或错误预算快速消耗；
- readiness 失败、Pod 重启循环、数据库连接耗尽；
- Redis 错误持续 1 分钟；
- AI 上游 429/5xx/timeout 激增或 token 成本异常；
- 未处理 billing provider event 增长；
- PostgreSQL 复制/WAL/备份延迟；
- 后台任务最老等待时间超过 5 分钟，或新增任意 `dead` 任务；
- 对象存储错误、`media.delete` 死信、过期 pending 媒体或用量异常增长；
- 审计持久化失败或 maintenance job 连续失败。

Prometheus 只采集低基数 route/method/status 标签，禁止加入 user ID、request
ID、邮箱、transaction ID 或模型 prompt。

## 常见事故

### PostgreSQL 不可用

readiness 应立即失败并停止接流量。禁止切换到本地缓存继续接受资产、旅行、订阅或同步写入。确认托管实例、网络和连接池后恢复；若涉及数据损坏，执行 PITR 流程。

### Redis 不可用

readiness 失败。登录、注册、验证码/密码邮件、账号 challenge 和 AI 分钟限流等认证敏感路径采用
fail-closed，不允许绕过风控；普通业务的全局 IP 保护可短暂 fail-open，但会以限频告警记录。PostgreSQL
业务数据不受影响。替换 Redis 后无需数据恢复。

### DeepSeek 故障或成本异常

在 `app.ai_routes` 禁用受影响 task，或把 task 指向已配置的受控提供商；客户端不能覆盖路由。检查
`ai_requests` 的稳定错误码和 token 聚合，禁止查看或记录用户 prompt。若 key
疑似泄露，先吊销并生成新 key，再更新 Secret Manager 和滚动重启。

### Apple 通知积压

确认验签、bundle、environment 和产品映射。重复通知可以安全重放；乱序事件不会覆盖更晚状态。不得手工把客户端声明写成有效 entitlement。修复配置后使用受控补偿程序重新处理
`processing_error` 事件并记录审计。

即使通知正常，也要每 15 分钟运行一次 `pnpm billing:reconcile`。它使用带租约的
`FOR UPDATE SKIP LOCKED` 批次领取到期订阅，调用 Apple Get All Subscription
Statuses，并再次验签其中每个 transaction/renewal JWS。退出码非零表示本批有失败；
查看 `reconciliation_error` 的稳定错误码和到期批次数量，禁止把 transaction ID、
原始 JWS 或 App Store API 响应写入日志/工单。多个实例可以并行，但总请求率不应逼近
Apple 限额。

### 邮件任务积压或死信

1. 查询 `app.jobs` 中 `pending` 的最老 `available_at`，以及 `dead` 的
   `type`、`attempts`、`last_error`；禁止导出或解密 payload。
2. 核对 worker 副本、SMTP 连通性和 `JOB_PAYLOAD_KEY_VERSION`。`last_error`
   只记录异常类型，不含收件地址、token 或 SMTP 响应正文。
3. SMTP 恢复后，可将确认属于暂时故障的死信改回 `pending`，同时清空租约字段并设置
   新的 `available_at`。操作必须走审计变更单，禁止降低 `attempts`。
4. 如果是密钥版本或 payload schema 不兼容，先回滚 worker；不要直接删除任务。
5. 已完成、取消和死信任务由 `maintenance:cleanup` 按 `JOB_RETENTION_DAYS` 清理。

### 对象存储故障或媒体删除积压

1. readiness 失败时先确认桶、区域、私网 DNS、workload identity 和 HeadBucket
   权限；不要临时开放公网桶。
2. 上传或下载签名异常时核对服务端时钟，以及目标存储对签名
   `Content-Length`、`Content-Type` 和 checksum query 的支持；禁止关闭完整性校验绕过。
3. `media.delete` 可以安全重试。只记录 asset/job ID，不把对象 URL、对象内容或签名 query
   写入工单和日志。
4. 每日维护会把过期 `pending` 预留转成删除任务。持续增长表示 worker、维护 CronJob
   或对象存储权限异常。
5. 对账数据库中 `deleted`/`purged_at` 与桶对象清单时只使用受控批处理；对象清单属于敏感
   元数据，差异删除先经过 dry-run 与审计。

### 账号删除任务失败

1. `account.purge` 进入死信即按高优先级隐私事故处理，记录 request ID，禁止读取 payload。
2. 查询删除请求的状态和不可逆 reference，核对 Apple revocation endpoint、client ID 与 credential
   key version；不得把 `processing` 账号手工恢复为 active。
3. Apple 暂时错误恢复后重排同一任务；缺少历史 credential client ID 时按 Apple
   手工撤销流程通知用户，同时仍须完成本系统数据删除。
4. 最终清除后验证用户主记录不存在、支付事实已匿名化、删除回执为 `completed`。
5. 从备份恢复数据时重新应用已完成删除回执，防止账号或个人数据复活。

### 凭据泄露

1. 立即吊销受影响提供商 key；
2. 保存不含 Secret 的证据和时间线；
3. 在 Secret Manager 写入新版本并滚动更新；
4. JWT 私钥泄露时轮换签名 key、提高用户 token version 或撤销会话；
5. 数据加密 key 泄露时先增加新 key version，再后台重加密，最后移除旧 key；
6. 检查审计和提供商用量，通知安全与合规负责人。

任何 Secret 一旦出现在聊天、工单正文或普通日志中，都按已泄露处理。

常规 JWT 轮换必须使用部署文档中的双公钥流程，并保留旧公钥至少一个 Access Token
TTL 加缓存余量。只有泄露事故才立即撤销会话；不能为了例行轮换让全部用户重新登录。

## 日常作业

- 每天：`pnpm maintenance:cleanup`；
- 每 15 分钟：`pnpm billing:reconcile`，并告警连续失败、租约反复超时或最老
  `reconcile_after` 延迟超过 2 小时；
- 每天：检查备份、WAL、未处理计费事件与媒体生命周期；
- 每周：依赖审计、镜像扫描、成本与配额复核；
- 每月：隔离恢复演练、权限复核、Secret 轮换演练；
- 每季度：威胁模型、数据保留和事故手册复审。
