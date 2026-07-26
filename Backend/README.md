# LingoTrip Backend

生产后端的模块化单体。架构和分阶段计划见：

- [`../docs/backend/ARCHITECTURE.md`](../docs/backend/ARCHITECTURE.md)
- [`../docs/backend/IMPLEMENTATION_PLAN.md`](../docs/backend/IMPLEMENTATION_PLAN.md)
- [`../docs/backend/THREAT_MODEL.md`](../docs/backend/THREAT_MODEL.md)

## 本地启动

需要 Node.js 24 和 pnpm 10：

```bash
pnpm install
cp .env.example .env
pnpm infra:up
pnpm db:migrate
pnpm dev
# 另开一个终端
pnpm worker
```

`.env` 不受版本控制。不要把 AI、数据库、JWT 或第三方凭据写入示例文件、源码或日志。

## 检查

```bash
pnpm check
pnpm build
pnpm test:integration
```

`test:integration` 需要先运行 `pnpm infra:up`。PostgreSQL 映射到本机
`54329`，Redis 映射到 `63799`，避免占用常见的默认端口。开发邮件进入 Mailpit，可在
`http://127.0.0.1:8025` 查看；私有媒体存入 MinIO，管理台位于 `http://127.0.0.1:9001`。

开发服务默认监听 `http://127.0.0.1:8080`：

- `GET /health/live`
- `GET /health/ready`
- `GET /.well-known/jwks.json`
- `GET /docs/openapi.json`（仅非生产环境）

邮箱认证端点位于
`/v1/auth`，支持注册、邮箱验证、登录、刷新令牌轮换、密码重置、设备会话列表和单设备/全设备撤销。刷新令牌重放会把整个 token
family 标记为 compromised。

所有 `/v1`
请求先经过 Redis 分布式固定窗口保护；登录同时按 HMAC 化的 IP 和规范化账号计数，注册、重发验证和找回密码另设小时级 IP/邮箱额度。Redis 不可用时认证敏感接口 fail-closed 返回 503，普通已认证业务可暂时 fail-open，并由 readiness 将异常实例摘流。响应包含标准化限流余量和重试时间，Redis
key 不保存原始邮箱或 IP。阈值可通过 `HTTP_GLOBAL_IP_MINUTE_LIMIT` 与 `AUTH_*_LIMIT`
环境变量按部署容量调整。

`GET /v1/account/export` 返回不含凭据和原始第三方 payload 的可移植一致性快照。
`DELETE /v1/account`
支持即时删除或带一次性取消 token 的冷静期删除；请求一旦接受即冻结账号并撤销全部会话，最终清除由 worker 执行。绑定 Apple 的账号会先调用 Apple
token revocation，再删除用户数据并匿名化依法需要保留的支付与审计事实。

配置 `APPLE_AUTH_ENABLED=true` 后会开放 Apple
challenge、login 和 link 端点。客户端先取得一次性 challenge，并把返回的 `nonce`
原样设置到 `ASAuthorizationAppleIDRequest`；随后把 identity
token、五分钟内有效且单次使用的 authorization code 与 `challengeId`
一并交给后端。后端校验 Apple 签名、issuer、audience、expiry 和 nonce，向 Apple 交换 authorization
code，并用 AES-256-GCM 加密保存 refresh
token。Apple 邮箱不会自动与已有邮箱账号合并；已有账号只能在已认证会话中显式绑定，避免错误接管。

`GET /v1/me` 返回跨平台权威用户快照。资料更新、购票和旅行等写请求必须携带UUID
`idempotency-key`；同一键重复提交会返回首次结果，换载荷复用会返回冲突。金币使用追加式账本并保留余额投影，机票是有状态库存。首次解锁城市在同一数据库事务中消费机票、写入解锁记录和旅行票根；已解锁城市往返不会消费机票。非生产环境额外开放
`/v1/dev/economy/*`，用于本地联调发放金币或机票，生产构建不会注册这些路由。

跨设备同步通过 `/v1/sync/snapshot` 建立权威快照，通过签名的不透明 cursor 顺序拉取
`/v1/sync/changes`。离线写入可批量提交到
`/v1/sync/commands`；每个 command 有独立 UUID 和幂等结果。业务变更、同步事件与命令回执在同一个数据库事务中提交。

跨平台用户内容通过 `/v1/content/records` 分页启动，并通过 `/v1/content/commands`
提交类型化的角色、会话、消息、收藏、记忆、答题记录与剧情断点。记录使用客户端稳定 ID、服务端递增版本和软删除墓碑；更新必须携带
`expectedVersion`，冲突会返回当前服务器记录而不会静默覆盖。分页 cursor 绑定账号且带 HMAC，第一页同时固定全局同步 cursor，分页期间发生的变更由
`/v1/sync/changes`
补齐。服务端校验每类 payload、父子关系、单记录大小与账号级资源上限，账号导出和删除也覆盖这些内容。

语音等二进制内容不进入 PostgreSQL 或 JSON 同步载荷。客户端先向 `/v1/media/assets`
预留稳定资产 ID，再按短时签名 URL 直传私有 S3 兼容桶；签名固定字节数、内容类型和 SHA-256，完成接口用对象元数据再次校验。只有
`ready`
且属于当前账号的资产能下载或被消息引用。删除先写数据库墓碑，再由持久 worker 幂等清除对象；过期未完成上传由每日维护任务回收。

订阅使用平台无关的 plan、store
product、transaction、subscription 和 entitlement 模型。Apple 适配器只接受官方 App Store
Server Library 验签后的 transaction，以及 App Store Server Notifications
V2；新购买必须把后端 `userId` 作为 StoreKit 2 的
`appAccountToken`，客户端不能自行声明会员等级。开发环境可用
`/v1/dev/billing/entitlements` 发放有时限的本地调试权益。生产定时运行
`pnpm billing:reconcile`，按租约批量调用 Get All Subscription
Statuses 补偿漏失通知，并再次验签响应中的交易与续订信息。

AI 请求统一经 `/v1/ai/completions` 或 `/v1/ai/stream`
转发。任务路由从数据库热读取，默认模型全部为
`deepseek-v4-flash`；客户端不能指定 provider、模型或提高服务端上限。系统按 entitlement 执行持久日配额、按用户执行 Redis 分钟限流，并只记录 task、模型、token 用量、延迟和稳定错误码，不保存 prompt 或模型回复。

启用 `ADMIN_API_ENABLED` 后，私网 `/internal/admin/ai/routes` 提供受轮换 operator
key 保护的 AI 路由读取、乐观锁更新、历史查询和回滚。每次变更需要 UUID 幂等键与原因，完整前后配置写入不可变 revision，operator
key ID 写入审计；运行时只接受 `AI_DEEPSEEK_ALLOWED_MODELS` 中的模型和严格白名单 provider
options。operator token 本身不写数据库或日志。

`/internal/metrics` 输出低基数 Prometheus 指标；生产环境必须用独立 bearer
token 保护。所有 HTTP 写操作会追加不含请求载荷的审计事件，IP 只保存 HMAC 摘要。部署环境应每天执行
`pnpm maintenance:cleanup`，按配置的保留期清理审计记录、AI 用量明细和已终结任务。

注册验证和密码重置邮件通过 PostgreSQL 持久任务投递：action
token 与加密 payload 在同一事务落库，worker 采用租约、`SKIP LOCKED`、指数退避和死信状态执行。生产必须提供稳定的任务加密 key；轮换时将旧版本放入
`JOB_PAYLOAD_PREVIOUS_KEYS`，直至旧任务全部终结。

生产环境需要持久的 Ed25519 签名密钥。以下命令仅把新密钥打印到当前终端，由操作者直接存入 Secret
Manager；不要把输出复制进仓库或聊天记录：

```bash
pnpm auth:generate-keys
```

Access Token 只使用 `AUTH_JWT_KEY_ID`
对应的当前私钥签发。轮换时把仍可能验证在线 token 的历史公钥以 `kid=base64(SPKI PEM)`
形式放入 `AUTH_JWT_PREVIOUS_PUBLIC_KEYS`；服务会在 `/.well-known/jwks.json`
同时发布当前和历史公钥，但永远不会用历史 key 签发。完整的无停机轮换和回滚顺序见部署文档。

停止本地依赖使用 `pnpm infra:down`。该命令默认保留数据库卷；只有显式执行
`docker compose down --volumes` 才会删除本地开发数据。

生产发布、回滚、备份恢复和事故处理分别见
[`../docs/backend/DEPLOYMENT.md`](../docs/backend/DEPLOYMENT.md)、
[`../docs/backend/BACKUP_RESTORE.md`](../docs/backend/BACKUP_RESTORE.md) 与
[`../docs/backend/OPERATIONS_RUNBOOK.md`](../docs/backend/OPERATIONS_RUNBOOK.md)。
