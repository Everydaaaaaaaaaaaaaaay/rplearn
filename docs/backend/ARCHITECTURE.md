# LingoTrip 生产后端架构

## 目标

后端为所有客户端维护一套平台无关的权威状态，并负责安全边界内的账号、订阅、AI、同步、虚拟经济、日志和数据治理。iOS 是第一个客户端，不是领域模型的宿主。

首期采用模块化单体，部署为 API 与 Worker 两个进程：

```text
iOS / Android / Web
        │ HTTPS + JSON / SSE
        ▼
┌───────────────────────────────┐
│ API                           │
│ Auth · Users · Sync · Billing │
│ Economy · AI Gateway          │
└───────────┬───────────┬───────┘
            │           │
            ▼           ▼
      PostgreSQL       Redis
       权威状态       缓存/限流/锁
            │
            ▼
      私有对象存储
       语音/用户媒体
            ▲
            │
┌───────────┴───────────────────┐
│ Worker                        │
│ 通知重试 · 收据核验 · 清理任务  │
│ 邮件 · 数据导出/删除 · 对账      │
└───────────┬───────────────────┘
            │
   Apple / DeepSeek / 邮件服务
```

## 目录边界

```text
Backend/
├── src/
│   ├── app/                 # 进程装配、HTTP 插件和统一错误
│   ├── config/              # 环境配置与启动校验
│   ├── db/                  # Schema、迁移入口和事务
│   ├── modules/
│   │   ├── auth/
│   │   ├── users/
│   │   ├── sync/
│   │   ├── economy/
│   │   ├── billing/
│   │   ├── ai/
│   │   └── audit/
│   ├── infrastructure/      # Redis、邮件、第三方适配器、遥测
│   └── shared/              # 跨模块值对象、错误、时钟和 ID
├── migrations/
├── test/
└── scripts/
```

模块只能通过导出的应用服务交互。HTTP Handler 不直接访问别的模块的数据表；第三方 SDK 不能泄漏到领域接口。

## 请求与身份模型

### 访问与刷新

- Access Token：非对称签名 JWT，包含 `sub`、`sid`、`aud`、`iss`、`iat`、`exp` 和权限版本；
- Refresh Token：32 字节以上密码学随机值，仅把带服务端 pepper 的摘要写入数据库；
- 轮换：成功刷新后旧令牌立即失效，新令牌属于同一 token family；
- 重放检测：已使用的刷新令牌再次出现时，撤销整个 family 和对应设备会话；
- 设备会话：记录平台、应用版本、最近活动、创建 IP 摘要和撤销时间，不把设备指纹当作唯一身份；
- 登出：撤销指定会话；“退出全部设备”递增权限版本并撤销所有会话。

### 身份提供商

统一身份表允许一个用户绑定多个身份：

- 邮箱密码：规范化邮箱、验证状态、Argon2id 密码摘要；
- Apple：验证签名、issuer、audience、nonce 和时效后，以 provider subject 绑定；
- 未来 Google 或企业身份：只增加适配器，不改变用户主键。

用户主键使用服务端生成的 UUIDv7；邮箱和第三方 subject 不能作为跨模块主键。

## 权威用户状态

服务器接受“操作”，不接受客户端声称的最终资产值。

例如旅行：

1. 客户端请求前往某城市，并提交幂等键；
2. 领域服务在事务内检查该城市是否已解锁；
3. 已解锁则直接更新当前位置，不扣机票；
4. 未解锁则校验机票余额，追加一条消费账本并创建解锁记录；
5. 写入用户变更序列；
6. 返回新的服务器版本和资产快照。

客户端提交 `tickets = 999`、`subscription = active` 或 `cityUnlocked = true` 都不会被接受。

## 同步协议

每个资源具备稳定 ID、服务器版本、`updatedAt` 和可选 `deletedAt`。每个用户维护单调递增 `changeSequence`。

### 下行

`GET /v1/sync/changes?cursor=...`

- 返回游标后的有序变更；
- 包含资源类型、资源 ID、操作、版本和最小必要数据；
- 删除通过墓碑传播；
- 游标过旧时要求客户端执行受控全量快照。

### 上行

`POST /v1/sync/commands`

- 每条命令带 `commandId`、`deviceId`、`baseVersion`、类型和载荷；
- 相同 `commandId` 返回首次处理结果；
- 领域规则决定合并、拒绝或产生冲突；
- 资产和权益类操作不使用 last-write-wins。

### 冲突策略

- 用户偏好：允许字段级 last-write-wins，使用服务器时间和版本；
- 收藏：集合式添加/删除；
- 对话草稿：客户端生成稳定 ID，服务端检测版本；
- 进度与解锁：服务端领域命令；
- 虚拟经济和权益：仅服务端账本与提供商事件。

### 用户内容记录

角色、会话、消息、收藏、角色记忆、答题记录和剧情断点使用
`/v1/content` 类型化协议。它们与金币、机票、解锁和订阅不同：允许客户端离线创建稳定
ID，但服务端保存权威版本并执行以下约束：

- 每个 upsert/delete 带独立 `commandId` 和 `expectedVersion`；
- 创建只能从版本 0 开始，修改和删除必须匹配当前版本；
- 会话必须引用本账号的角色，消息必须引用会话，记忆必须引用角色；
- 删除父记录前必须先处理仍存活的子记录；
- payload 经过按资源类型的严格 Schema 校验，不接受任意 JSON 字段；
- 单记录限制 128 KiB，并对各类记录设置账号级数量上限；
- 删除保留墓碑并进入全局 `changeSequence`，换机不会让已删内容复活。

大账号启动不把全部内容塞入一个响应。客户端先分页读取稳定键空间；第一页返回当时的全局同步
cursor，完成分页后重放该 cursor 之后的变更。因此，即使记录在分页期间创建、更新或删除，也不会遗漏。分页 cursor 使用账号绑定的
HMAC，不接受客户端伪造边界或跨账号复用。

## 用户媒体

语音内容按敏感个人数据处理，二进制本体存入默认拒绝公网访问的 S3
兼容私有桶，PostgreSQL 只保存权威资产元数据和生命周期：

1. 客户端生成稳定 UUID，提交用途、精确字节数、MIME 和 SHA-256；
2. 服务端在锁定用户行后同时检查总字节与资产数量额度，并分配只含
   `userId/assetId` 的对象键；
3. 上传 URL 只存活五分钟，签名固定 `Content-Length`、`Content-Type`，并把 checksum
   与元数据纳入签名；
4. 客户端直传后调用 complete；服务端执行 HEAD，逐项匹配大小、类型和 checksum 后才将
   状态从 `pending` 改为 `ready`；
5. 内容记录只能引用本账号已 ready 的语音资产；下载 URL 同样短时有效且响应禁止缓存；
6. 删除先写墓碑并在同一事务创建加密持久任务，worker
   幂等删除对象；仍被消息引用的资产拒绝删除；
7. 未完成预留自动过期并进入删除任务；账号永久删除必须先清空对象前缀，失败则整个删除
   任务重试。

对象桶启用 Block Public Access、禁用 ACL、静态加密、TLS、版本控制和生命周期规则。对象
存储不是业务权威来源：没有通过 complete 的孤儿对象不可被客户端读取，数据库恢复后也需
依据删除回执和生命周期规则重新收敛。

## 订阅与权益

领域对象分为：

- Product：平台无关的商品定义；
- Store Product Mapping：Apple、Google、Web 的商品 ID 映射；
- Transaction：原始购买事实的规范化记录；
- Subscription：续订周期、状态和宽限期；
- Entitlement：客户端实际可用的能力；
- Provider Event：第三方通知的幂等事件记录。

Apple 首期流程：

1. 客户端上传签名交易或服务器收到 App Store Server Notification；
2. 服务端验证 JWS 证书链、签名、bundle ID、environment、transaction ID 和时效；
3. 以 transaction ID / notification UUID 幂等落库；
4. 归一化订阅状态并计算权益；
5. 客户端只读取统一 Entitlement，不解释 Apple 状态。

生产环境同时使用服务器通知与主动补查，避免只依赖客户端上报。主动补查按数据库租约批量
调用 Get All Subscription Statuses，重新验签返回的 transaction/renewal JWS，并以
`provider_event_at` 拒绝乱序回退；活跃、宽限/扣款重试和失效状态使用不同检查周期，
临时故障指数退避。未来 Google Play 或 Web 支付复用相同权益模型。

## AI 网关

### 任务路由

客户端提交稳定任务名，不提交供应商密钥或任意模型名。初始任务包括：

- `chat.fast`
- `chat.coach`
- `chat.roleplay`
- `translation`
- `grammar.explain`
- `memory.extract`
- `encounter.generate`
- `quiz.generate`
- `speech.feedback`
- `content.moderate`

每个路由可配置：

- provider、model、enabled；
- thinking 模式、temperature、max output tokens；
- 超时、重试、并发和熔断阈值；
- 免费/订阅用户的每日与每分钟配额；
- 系统提示词版本和允许的工具；
- 是否流式、是否需要结构化 JSON。

开发配置中全部路由默认使用 DeepSeek 的 `deepseek-v4-flash`。配置保留切换能力，生产修改经过审计，不让客户端直接覆盖安全参数。

管理面仅通过私网 `/internal/admin` 暴露，使用可并行轮换的高熵 operator key。AI 路由变更
必须携带期望版本、独立幂等键和变更原因；事务同时更新活动配置并追加完整前后快照。
历史版本可回滚，但仍要通过当前部署的模型 allowlist 和 provider-options 严格 schema。
provider options 永远不能覆盖服务端生成的 messages、model、token 上限、stream 或
匿名化 `user_id`。

### 安全与隐私

- DeepSeek API 密钥只来自运行时 Secret；
- 为上游构造不可逆、无 PII 的用户标识；
- 默认不记录完整输入和输出；
- 记录 token 用量、耗时、路由、模型、状态和费用估算；
- 限制输入长度、输出长度、工具集合和总执行时间；
- 系统提示词与用户内容分层，工具参数再次做 Schema 校验；
- 提示词注入不能获得服务端密钥、内部配置或任意网络访问；
- SSE 在客户端断开时主动取消上游请求。

## 数据分级

| 等级         | 示例                                    | 规则                                   |
| ------------ | --------------------------------------- | -------------------------------------- |
| Secret       | 密码、刷新令牌、AI 密钥、Webhook 密钥   | 不写日志；摘要或加密保存；最小权限访问 |
| 敏感个人数据 | 邮箱、Apple subject、语音内容、导出文件 | 加密传输；限制保留；支持导出和删除     |
| 业务敏感     | 订阅、权益、资产账本、审计记录          | 服务端权威；不可由客户端覆盖           |
| 一般数据     | 偏好、公开内容 ID、应用版本             | 仍受租户隔离和访问控制                 |

数据库备份、导出文件和消息队列载荷使用同等分级。日志只记录必要元数据。

## 可观测性

- 应用日志：Pino JSON，字段白名单与递归脱敏；
- 访问日志：请求 ID、路由模板、状态、耗时、响应尺寸；
- 审计日志：身份、计费、权益、后台配置和高风险操作，追加写入；
- 指标：请求率/错误率/延迟、数据库池、Redis、AI token/费用/错误、登录失败、收据验证积压；
- 追踪：OpenTelemetry 贯穿 API、数据库、Redis 和上游 HTTP；
- 健康检查：`/health/live` 只表示进程存活，`/health/ready` 检查依赖与迁移状态；
- 告警：SLO 燃尽、认证异常、AI 成本突增、通知积压和数据库容量。

## 部署拓扑

本地开发使用 Docker Compose 启动 PostgreSQL、Redis、API 和 Worker。生产部署要求：

- API 至少两个无状态副本，负载均衡器终止 TLS；
- Worker 可独立扩容，任务有租约、幂等和死信处理；
- 托管 PostgreSQL 开启多可用区、自动备份和时间点恢复；
- 托管 Redis 开启认证和网络隔离；
- 私有对象存储启用静态加密、版本控制、访问日志和生命周期；
- Secret 由部署平台注入并支持轮换；
- 数据库迁移作为独立发布步骤；
- 容器使用非 root 用户、只读文件系统和固定依赖版本；
- 生产、预发布和开发使用独立账号、数据库和第三方应用配置。

Compose 只用于本地联调，不声明生产高可用。

## API 兼容性

- 字段只做向后兼容增加；删除或改变语义需要新版本；
- 客户端上报平台、应用版本和 API 能力；
- 错误响应固定包含 `code`、`message`、`requestId`，可选 `details`；
- 服务端时间使用 UTC RFC 3339；
- 金额使用最小货币单位整数，虚拟资产使用整数；
- ID 对客户端是不透明字符串；
- 分页使用不透明游标，不暴露数据库 offset。
