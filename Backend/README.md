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
`http://127.0.0.1:8025` 查看。

开发服务默认监听 `http://127.0.0.1:8080`：

- `GET /health/live`
- `GET /health/ready`
- `GET /docs/openapi.json`（仅非生产环境）

邮箱认证端点位于
`/v1/auth`，支持注册、邮箱验证、登录、刷新令牌轮换、密码重置、设备会话列表和单设备/全设备撤销。刷新令牌重放会把整个 token
family 标记为 compromised。

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

订阅使用平台无关的 plan、store
product、transaction、subscription 和 entitlement 模型。Apple 适配器只接受官方 App Store
Server Library 验签后的 transaction，以及 App Store Server Notifications
V2；新购买必须把后端 `userId` 作为 StoreKit 2 的
`appAccountToken`，客户端不能自行声明会员等级。开发环境可用
`/v1/dev/billing/entitlements` 发放有时限的本地调试权益。

生产环境需要持久的 Ed25519 签名密钥。以下命令仅把新密钥打印到当前终端，由操作者直接存入 Secret
Manager；不要把输出复制进仓库或聊天记录：

```bash
pnpm auth:generate-keys
```

停止本地依赖使用 `pnpm infra:down`。该命令默认保留数据库卷；只有显式执行
`docker compose down --volumes` 才会删除本地开发数据。
