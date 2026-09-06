# LingoTrip

LingoTrip 是一款原生 SwiftUI 英语学习 App。用户以世界旅行为线索，与城市中的 AI
角色聊天、练习语音、学习词汇和语法、推进剧情，并收集机票与票根。

仓库同时包含 iOS 客户端和生产后端。客户端本地优先；登录后，账号、订阅、虚拟资产、
旅行进度和跨设备内容由后端同步并校验。

## 开始开发

客户端需要 macOS、Xcode 26+、[XcodeGen](https://github.com/yonaskolb/XcodeGen) 和
[Git LFS](https://git-lfs.com/)；SQLite 词典、模型权重和 3D/视频资源通过 LFS 获取：

```bash
Scripts/bootstrap-worktree.sh
Scripts/run.sh
```

`code-map.sh` 是按需符号查询工具。`Scripts/check-architecture.sh` 默认只检查 iOS 路径/Feature 边界；
后端或两端检查分别传 `--backend`、`--all`。构建脚本从 `project.yml` 生成本地 `LingoTrip.xcodeproj`。
不要提交生成的工程或 `build/`，
也不要在 `Packages/LingoKit` 中直接运行 `swift build`。脚本用当前工作树的锁串行化其构建、
测试和安装；该锁不协调其他工作树或 Xcode IDE。每个工作树使用自己的 DerivedData 和
可配置的 Swift Package 缓存；同时测试时选择各自设备，避免争用同一模拟器。

对话提示词、回复分条等纯逻辑改动优先运行 `Scripts/test-conversation.sh`；它不构建宿主 App
和 SpeechKit，通常远快于完整测试。其他逻辑用 `Scripts/test.sh -only-testing:LingoTripTests/<Suite>`
选相关套件；共享契约或发布范围需要时再扩大，专项后不强制全量。验证选择见 [开发速查](docs/development.md)。
需要安装/启动模拟器时用 `Scripts/run.sh`。需要固定模拟器时设置
`LINGOTRIP_SIMULATOR_UDID`。

真机调试前复制 `Config/Signing.local.xcconfig.example` 为
`Config/Signing.local.xcconfig`，填写自己的 Team ID；若共享 App ID 不属于该 Team，再
覆盖 `LINGOTRIP_BUNDLE_ID`。该文件只影响 Debug，不会改变 Release 归档。

Release 固定使用现有 App Store Connect 记录的 `com.tiantian.lingotrip` 与项目分发
团队，后续版本不再更换标识。日常归档运行 `Scripts/archive.sh`，脚本会用 Git 提交数
生成递增的 Build Number；需要覆盖版本时可设置 `LINGOTRIP_MARKETING_VERSION` 或
`LINGOTRIP_BUILD_NUMBER`。

后端需要 Node.js 24、pnpm 10、PostgreSQL 17 和 Redis，启动方式见
[`Backend/README.md`](Backend/README.md)。

## 仓库结构

```text
App/                    iOS App 入口、组合根和随包资源
Packages/LingoKit/      客户端模块、领域实现和测试
Backend/                TypeScript API、Worker、迁移和部署文件
Scripts/                本地开发、构建、测试与架构检查入口
Tools/                  美术流水线与离线数据处理工具
docs/                   架构、产品与按需运维说明
project.yml             Xcode 工程配置的唯一事实源
```

客户端模块的直接依赖以
[`Packages/LingoKit/Package.swift`](Packages/LingoKit/Package.swift) 为准：

```text
App 组合根
├── Feature：Auth / Home / Chat / Onboarding / Placement / Story / Roster /
│            Map / Favorites / Settings
├── 领域与集成：DomainKit / StoryEngine / SyncKit
├── 服务：BackendKit / BillingKit / LLMKit / MediaKit / SpeechKit /
│        RealtimeVoiceKit / DictKit / PersistenceKit
└── 基础：CoreKit / MascotKit / DesignSystem
```

Feature 之间不直接依赖。跨页面导航和服务选择在 `App/RootView.swift` 与
`App/AppEnvironment.swift` 中完成。

## 数据边界

- 游客使用本地领域服务，离线也能完成主要体验。
- 登录用户的资产、权益和进度由服务端权威接口处理。
- SwiftData 负责本地投影、内容 Outbox、会话偏好与语音上传/删除队列；所有版本都通过显式迁移计划升级，迁移失败会保留原库并报错。
- NPC 的公共身份、11 位旅伴号和永久头像归服务端注册表管理；备注、关系、人格成长等用户私有状态独立保存并随账号内容同步。
- AI 请求统一经过后端；客户端不保存模型供应商密钥。
- 用户内容采用稳定 ID 和版本号同步，语音二进制存入私有对象存储。

## 轻量开发约定

- 一个逻辑工作一个提交，不把无关修改混入同一提交。
- 新增 Swift 文件或模块依赖后运行 `Scripts/test.sh`。
- 生产源码单文件超过 800 行时优先按职责拆分，并运行 `Scripts/check-architecture.sh`。
- 修改持久模型时保留旧 `VersionedSchema`、递增版本并补迁移测试；不得用删库或重置数据代替迁移。
- 跨 actor 传递 `Sendable` DTO，不把 SwiftData 实体带出仓库 actor。
- 文档只记录稳定边界、设计意图和操作入口；完成的计划与阶段快照不长期保留。

更多说明见 [`docs/README.md`](docs/README.md)。日常开发通常只需阅读本文件和对应模块代码。
