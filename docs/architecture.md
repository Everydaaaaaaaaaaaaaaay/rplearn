# 工程架构

## 总览

LingoTrip 是一个包含 iOS 客户端和生产后端的单仓库：

```text
iOS SwiftUI
├── SwiftData 本地投影与 Outbox
├── Apple 语音、翻译和 StoreKit
└── HTTPS / JSON / SSE
          │
          ▼
Fastify API ── PostgreSQL
     │         权威账号、权益、资产、进度和用户内容
     ├────── Redis
     │       限流、短期协调和缓存
     ├────── 私有对象存储
     │       语音媒体
     └────── Worker
             邮件、删除、清理和外部服务重试
```

## 客户端

App 壳的主入口与支持文件是：

- `LingoTripApp.swift`：SwiftUI 生命周期。
- `AppEnvironment.swift`：创建并持有服务、Store 与同步协调器。
- `RootView.swift`：认证状态、四个 Tab 和依赖注入。
- `AppNavigationState.swift`：跨 Feature 导航状态。
- `LegacyTabBarCapsuleInstaller.swift`：旧系统 Tab Bar 的隔离适配。

其余代码位于单一本地 Swift Package 中。24 个 Target 按职责分为：

| 层 | 模块 |
|---|---|
| Feature | Auth、Home、Chat、Onboarding、Placement、Story、Roster、Map、Favorites、Settings |
| 领域与集成 | DomainKit、StoryEngine、SyncKit |
| 服务 | BackendKit、BillingKit、LLMKit、MediaKit、SpeechKit、RealtimeVoiceKit、DictKit、PersistenceKit |
| 基础 | CoreKit、MascotKit、DesignSystem |

Feature 只依赖下层模块，Feature 间跳转由组合根注入。模块直接依赖以
`Packages/LingoKit/Package.swift` 为准，不从目录嵌套推断。

较大的 Target 可以在自身目录内按 `Contracts / Models / Views / Stores` 等职责分组；
小 Target 保持扁平，避免只为形式增加目录。

## 本地状态与账号状态

`RootView` 根据认证状态选择两套领域网关：

- 游客：本地完成资料、奖励、旅行和进度操作。
- 登录用户：通过 `BackendUserStateCoordinator` 调用服务端领域命令。

登录失败不会阻塞启动，客户端会回退到游客空间。App 回到前台时同步用户状态、内容、
语音媒体和订阅。

SwiftData 只保留一个当前开发基线，包含用户内容、同步 Outbox、语音上传队列和旅程状态。
正式发布前允许随模型调整而重置测试数据；有真实用户后再冻结基线并引入版本迁移。

SwiftData 实体留在 PersistenceKit 的 actor 内；UI 和领域服务使用 `Sendable` DTO。

## 核心数据流

### 聊天

```text
用户输入
→ 本地消息落库
→ 教练审核旁路
→ 记忆与历史窗口组装
→ 后端 AI SSE
→ 流式更新本地消息
→ 小测解析、关键词标注、奖励与记忆压缩
→ 内容 Outbox 同步
```

提示词在 `DomainKit/Conversation`，模型协议和路由在 `LLMKit`，页面状态在
`ChatFeature/ChatViewModel.swift`。

### 权威领域操作

购票、首次旅行、剧情奖励和订阅权益不能由客户端直接改最终值。服务端验证操作、写账本或
状态、追加同步事件，再返回新快照。相同幂等键重复请求返回首次结果。

### 用户内容

角色、会话、消息、收藏、记忆、小测和剧情断点允许离线创建。客户端使用稳定 ID、
`expectedVersion` 和持久 Outbox 上传；冲突时以服务端当前记录为基础重放仍然有效的本地意图。

### 语音媒体

本地录音先进入上传队列，再向后端预留资产 ID，通过短时签名 URL 直传对象存储。对象校验
完成后，消息内容才引用远端资产。二进制不进入 PostgreSQL 内容载荷。

## 后端

后端是模块化单体，API 与 Worker 共享配置、数据库 Schema 和模块服务。

- `auth / account`：邮箱、Apple、设备会话、导出和删除。
- `domain`：资料、金币、机票、旅行和剧情奖励。
- `billing`：StoreKit 交易、订阅与统一权益。
- `ai`：DeepSeek 路由、配额、流式中转和审计配置。
- `content / sync`：版本化内容、墓碑和有序变更。
- `media`：私有语音资产生命周期。
- `jobs`：持久任务、租约、重试和死信。
- `observability / abuse`：日志、指标、审计和限流。

模块通过 `types.ts` 和 service 契约协作，不导入其他模块的 `repository.ts` 或 `schema.ts`。
共享用户表位于 `src/db/user-schema.ts`，事务内的同步变更写入位于
`src/infrastructure/sync-change-writer.ts`。本地 `pnpm architecture` 检查模块循环和实现泄漏。

PostgreSQL 是唯一业务事实源；Redis 中的数据必须可丢失或重建。第三方 SDK 不应泄漏到
领域接口。

## 常见改动入口

| 需求 | 入口 |
|---|---|
| 页面或交互 | 对应 `*Feature`，跨 Feature 导航改 `RootView` |
| 业务规则 | `DomainKit`，并补对应测试 |
| 本地模型或查询 | `PersistenceKit` |
| 服务端 API 契约 | `BackendKit` 与 `Backend/src/modules/*` |
| AI 任务 | `DomainKit/Conversation`、`LLMKit`、后端 `ai` |
| 城市和剧情 | `regions.json`、`DomainKit/Story`、`App/Resources/Stories` |
| 视觉原语 | `DesignSystem`；业务专属组件留在 Feature |

新增抽象前先确认它确实被多个调用方需要。这里的分层用于明确所有权，不要求每项功能都新增
模块、协议或文档。
