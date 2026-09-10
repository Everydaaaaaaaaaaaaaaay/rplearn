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

其余代码位于单一本地 Swift Package 中，按职责分为：

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

`RootView` 的生产入口固定为欢迎页 → 登录页 → 账号工作区 → 账号首启流程 → 主界面。
未认证时不创建业务 SwiftData 容器，也不存在可关闭登录页或游客工作区。登录用户通过
`BackendUserStateCoordinator` 调用服务端领域命令；App 回到前台时同步用户状态、内容、
语音媒体和订阅。

每个 `users.id` 对应独立的 `Application Support/LingoTrip/Accounts/<user-id>/LingoTrip.store`。
切号先卸载旧工作区，再打开目标账号数据库；退出登录不删除离线缓存。钥匙串中仍有效的已验证
会话在弱网下可以恢复身份：只有本地档案和同步游标同时存在时才开放离线工作区，首次登录或
首次内容同步仍必须联网。主动消息偏好、未读缓存、剧情断点和语音文件也按账号命名空间保存。

账号只以 `users.id` 作为业务数据归属；邮箱、Apple、Google 等登录入口都是可增删的
`user_identities`。外部身份用 `(provider, provider_subject)` 全局唯一定位账号，不以邮箱相同
自动合并；已有账号增加登录方式必须在已认证会话中显式绑定。每次登录生成独立
`device_sessions`，用户可查看并撤销其他设备。解除登录方式需要最近 10 分钟内建立的会话，
且服务端始终保留至少一种登录方式；Apple 解除绑定和账号删除会先撤销服务端保存的 Apple
refresh token。历史版本已经产生的游客旅程只在第一次登录迁移时通过幂等认领进入同一个
`users.id`；当前产品不再创建或展示游客身份。

iOS 使用原生 `AuthenticationServices` 获取一次性授权码、identity token、nonce 及 Apple 用户
标识；服务端验证 token 后交换并加密保存 refresh token。客户端只在钥匙串保存本账号对应的
Apple 用户标识，用于启动时检查授权状态，不保存 Apple 私钥或服务端 refresh token。

SwiftData 包含用户内容、同步 Outbox、会话置顶/已读游标、语音上传与删除队列和旅程状态。
`LingoMigrationPlan` 管理冻结的版本 Schema 与逐版本迁移；迁移失败必须保留原库并向上报告，不能通过删库或重置用户数据恢复。对早期没有版本校验和的开发库，仅允许 SwiftData 自动轻量迁移兜底。

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

会话置顶和已读游标属于账号内容，不使用设备级 `UserDefaults`。删除语音消息时先同步消息墓碑；确认墓碑到达服务端后，再由持久删除队列删除远端对象。离线或暂时失败按指数退避重试，避免留下不可达媒体或先删媒体后仍有消息引用。

### 公共 NPC 与私有关系

```text
外出活动优先复用符合场景的公共角色
→ 没有复用时生成角色卡及结构化人物指纹
→ 后端同时检查公共角色与待头像角色；定位过近则返回明确维度供客户端重生
→ 通过权威查重后注册不可变公共身份并分配 11 位校验旅伴号
→ 最后才由头像池按年龄段与性别呈现标签匹配、事务锁定并永久领取
→ 服务端确认或建立待头像预留后，客户端才保存新的本地候选角色
→ 用户侧备注、好友状态、偏好、关系数值和成长分支独立演进
```

公共身份可通过旅伴号跨用户检索，同一 NPC 的基础资料和头像保持一致；用户对 NPC 的接触造成的人格变化只进入该用户的私有成长分支，不改写全局人格。头像匹配不依据国籍或地域推断外貌。头像覆盖不足时，已经通过人物查重的原始身份进入持久待分配队列，联系人页和前台协调器会自动重试。人物多样性检查的字段、阈值、并发与兼容策略见 [NPC 人物定位多样性](npc-persona-diversity.md)。

这是角色库能力的数据流。活动脚本负责可选行动和场景文案，社交偶遇由
`SocialEncounterModel` 调用 `EncounterService.generateEncounter`，已有角色的现场回复由
`SocialDialogueService` 生成；角色生成与实际活动入口必须分别验收。

### 语音媒体

本地录音先进入上传队列，再向后端预留资产 ID，通过短时签名 URL 直传对象存储。对象校验
完成后，消息内容才引用远端资产。二进制不进入 PostgreSQL 内容载荷。

### 词典例句翻译

词卡先用随包 ECDICT/WordNet 数据同步展示英文例句；中文整句翻译和该词在句中的单一语境义
通过 BackendKit 异步查询公共缓存。缓存未命中只影响例句下方的翻译状态，不阻塞词卡显示。
登录用户可以触发服务端持久任务；Worker 持有 AI 凭据、生成结构化结果并回填
PostgreSQL，客户端不能提交译文污染公共缓存。常用词的 Luna 预生成结果只能经 operator 接口
导入，来源版本、例句哈希、义项指纹、模型版本和提示版本共同决定缓存身份。

## 后端

后端是模块化单体，API 与 Worker 共享配置、数据库 Schema 和模块服务。

- `auth / account`：可扩展登录身份、邮箱、Apple、设备会话、导出和删除。
- `domain`：资料、金币、机票、旅行和剧情奖励。
- `billing`：StoreKit 交易、订阅与统一权益。
- `ai`：DeepSeek/OpenRouter 适配、按任务版本化路由、模型目录、配额、流式中转、成本分析和审计配置。
- `dictionary-translation`：例句翻译公共缓存、安全解析、可信预生成导入和异步回填。
- `content / sync`：版本化内容、墓碑和有序变更。
- `media`：私有语音资产生命周期。
- `npc`：公共 NPC 注册表、旅伴号、头像领取和用户私有关系映射。
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
