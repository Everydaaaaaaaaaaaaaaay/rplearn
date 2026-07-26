# 后端部署基线

## 运行拓扑

生产环境使用无状态 API 副本、独立后台 worker 副本、托管 PostgreSQL、托管 Redis、SMTP
提供商和外部 Secret Manager。PostgreSQL 是唯一权威业务存储；Redis
丢失只影响短时 challenge、限流窗口等可重建数据。公网入口必须在负载均衡或 Ingress
终止 TLS 1.2+，容器自身不直接暴露公网端口。

`Backend/Dockerfile` 生成 Node 24、非 root、只含生产依赖的镜像。部署镜像必须使用 digest
固定，不使用浮动 tag。`Backend/ops/kubernetes` 是最低安全基线；上线时由部署系统注入
ConfigMap 和 Secret，不把值写进 manifest。

## 发布顺序

1. CI 完成格式、lint、类型、单元测试、真实 PostgreSQL/Redis 集成测试、生产依赖审计和镜像构建。
2. 为镜像生成 SBOM，并由镜像扫描器阻止 critical/high 且无豁免的漏洞。
3. 确认最近一次 PostgreSQL 基础备份和 WAL/PITR 流连续可用。
4. 使用与 API 完全相同 digest 的一次性 Job 执行 `node dist/cli/migrate.js`。
5. 等迁移 Job 成功，再滚动更新 API 与 worker；readiness 失败的 API Pod 不接收流量。
6. 验证 live、ready、metrics、注册/刷新、同步、计费沙盒通知与 AI canary。
7. 观察错误率、P95/P99、数据库连接、Redis 错误和 AI 上游错误至少一个正常业务峰值窗口。

迁移只允许向前追加，并在至少一个发布窗口内保持旧应用版本可读。破坏性列删除、重命名和
`NOT NULL` 收紧必须按 expand → backfill → contract 跨多个版本完成。

## 必需 Secret

- PostgreSQL、Redis、SMTP 凭据；
- Ed25519 JWT 私钥、公钥、key ID 与 token HMAC pepper；
- 仍在轮换观察期内的 JWT 历史公钥；
- DeepSeek API key；
- metrics 独立 bearer token；
- 管理面启用时的一个主 operator token 和一个预置轮换 token；
- 后台任务 payload AES-256-GCM key 与 key version；
- 私有媒体桶名称、区域；非 workload identity 环境才注入对象存储访问凭据；
- Apple 登录私钥与 Apple credential AES-256-GCM key；
- 启用 Apple Billing 时的 App Apple ID、Apple PKI 根证书，以及独立的 In-App
  Purchase issuer ID、key ID 与 PKCS#8 私钥。

生产配置校验采用 fail-closed：缺少数据库、Redis、SMTP、持久 JWT、DeepSeek 或 metrics
保护凭据时进程拒绝启动。Secret 只通过运行时环境或挂载式 Secret
注入，禁止进入镜像层、CI 日志、崩溃报告或聊天记录。

`/internal/admin` 只能放在私网 ingress、VPN 或零信任代理之后，不能配置到公共移动端
API 域名的外部路由。轮换时先追加新 key ID/token，验证审计中的新 key ID，再移除旧 key；
token 不进入数据库。`AI_DEEPSEEK_ALLOWED_MODELS` 是部署层安全边界，先滚动放行新模型，
再通过管理面修改任务路由。

生产 OpenTelemetry Collector 使用私网 TLS 地址。API 和 Worker 分别设置稳定的
`OTEL_SERVICE_NAME`，并把不可变镜像/发布编号写入 `APP_VERSION`。通过
`OTEL_TRACING_ENABLED=true` 启用，`OTEL_TRACE_SAMPLE_RATIO` 首发建议为 `0.1`；
Collector 鉴权放入 Secret `OTEL_EXPORTER_OTLP_HEADERS`。先在预发布确认 span 不含 query、
认证 header、交易/对象 ID 或用户内容，再逐步提高采样率。Collector 故障不能阻塞 API，
但连续导出失败必须告警。

数据库迁移 Job 只注入具备 DDL 权限的 `MIGRATION_DATABASE_URL`，执行
`node dist/cli/migrate.js` 后立即销毁；API、Worker 和其它 CronJob 只注入低权限
`DATABASE_URL`，不能获得迁移 Secret。开发/CI 未设置迁移 URL 时命令才兼容回退到
`DATABASE_URL`。

部署平台另建每 15 分钟一次的同镜像 CronJob，命令为
`node dist/cli/reconcile-apple-billing.js`。CronJob 与 API 使用同一版本、数据库和 Apple
Billing Secret；允许并发实例依靠数据库租约分片，但禁止配置无限并发。

API 在账号业务事务中写入加密任务，只有 worker 执行 SMTP 投递。worker 可横向扩容，
数据库租约与 `FOR UPDATE SKIP LOCKED` 负责互斥领取；失败任务指数退避，达到最大次数后
进入 `dead`。API 和 worker 必须通过 `JOB_PAYLOAD_PREVIOUS_KEYS` 同时保留仍有未完成任务
引用的历史 key version；确认旧版本任务全部结束并超过保留期后才能移除旧 key。

## 私有媒体桶

生产设置 `MEDIA_STORAGE_ENABLED=true` 并提供 `MEDIA_S3_BUCKET` 与区域。优先让 API 和
worker 使用不同、最小权限的 workload identity；只有兼容存储不支持工作负载身份时才成对
注入 access key 与 secret。API 需要 `HeadBucket`、指定前缀的
`PutObject/GetObject/HeadObject` 签名权限，worker 额外需要批量删除权限。

桶必须阻止全部公网访问、禁用 ACL、强制 TLS、启用默认静态加密和版本控制，并把读写数据
事件送入云审计。生命周期至少覆盖：删除标记和非当前版本清理、未完成 multipart
上传清理，以及数据库任务异常时的孤儿对象兜底保留期。不能设置允许匿名 GET 的桶策略。
跨域只在 Web 客户端上线时为明确的生产 origin、PUT/GET 方法和必要 header 开白名单；
iOS 不需要 CORS。

发布前用真实目标存储运行媒体集成测试，验证签名的 `Content-Length`、`Content-Type` 和
checksum 兼容性。`/health/ready` 会执行 HeadBucket；对象存储不可用的实例不接收流量。
worker 的 `media.delete` 死信和 `pending` 资产年龄必须进入告警。MinIO
只供本地联调，不能作为当前 Compose 配置直接用于生产。

## JWT 无停机密钥轮换

JWT 私钥只存在 Secret Manager，历史配置只保存公钥。每次轮换使用全新的、不可复用的
`kid`：

1. 在受控终端执行 `pnpm auth:generate-keys`，把新私钥、公钥和 key ID 直接写入 Secret
   Manager，禁止进入仓库、聊天或 CI 输出。
2. 建立一个原子 Secret 版本：把新 key 配置为 `AUTH_JWT_PRIVATE_KEY`、
   `AUTH_JWT_PUBLIC_KEY` 和 `AUTH_JWT_KEY_ID`，同时把旧公钥加入
   `AUTH_JWT_PREVIOUS_PUBLIC_KEYS`。格式为
   `old-kid=BASE64_SPKI_PEM`，多个历史 key 用逗号分隔。
3. 滚动发布全部 API 副本。进程启动时会验证当前私钥与公钥确实配对；key ID
   重复、未知算法或无效历史公钥都会拒绝启动。确认旧 Pod 已完全排空。
4. 请求 `/.well-known/jwks.json`，确认新旧 `kid` 均存在；再用新登录签发的 token
   验证 `kid` 已切换到新 key。JWKS 最长缓存五分钟。
5. 至少保留旧公钥一个 Access Token TTL（当前为 15 分钟），再加发布时钟偏差和
   JWKS 缓存余量。生产建议观察不少于 30 分钟，并确认没有旧版本 Pod 继续签发。
6. 从 `AUTH_JWT_PREVIOUS_PUBLIC_KEYS` 移除旧公钥，滚动发布并验证 JWKS 只剩仍有效的
   key。

若步骤 3 后需要应用回滚，优先回滚应用镜像但保持新 key 为当前签发 key，并继续发布旧
公钥。只有确认必须恢复旧 key 签发时才重新启用保管中的旧私钥，同时把新公钥放进历史
列表；否则回滚会立即拒绝刚签发的新 token。当前私钥泄露时不能等待观察窗口：立即切换
新 key，撤销全部会话或提升 token version，并按安全事故流程处理。

## 回滚

应用回滚只切回上一镜像 digest，不回滚已执行的数据库迁移。若新版本产生不可兼容写入：

1. 先停止新版本流量；
2. 启用对应功能开关或只读保护；
3. 回滚到仍兼容当前 schema 的上一 digest；
4. 以新迁移修复数据，不执行手工 `DROP` 或 migration table 篡改。

若数据库数据已被破坏，按恢复手册在隔离实例执行 PITR，验证后通过受控切换恢复服务。

## 本地完整容器联调

```bash
cd Backend
DEEPSEEK_API_KEY='从本机安全环境注入' docker compose --profile app up --build --wait
```

API 为 `http://127.0.0.1:8080`，worker 自动处理邮件和媒体删除任务，Mailpit 为
`http://127.0.0.1:8025`，MinIO 控制台为
`http://127.0.0.1:9001`。Compose 开发配置使用临时 JWT
密钥，容器重启会使现有 access token 失效；生产绝不能使用这一开发行为。
