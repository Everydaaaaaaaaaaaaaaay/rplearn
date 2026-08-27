# LingoTrip

LingoTrip 是一款原生 SwiftUI 英语学习 App。用户以世界旅行为线索，与城市中的 AI
角色聊天、练习语音、学习词汇和语法、推进剧情，并收集机票与票根。

仓库同时包含 iOS 客户端和生产后端。客户端本地优先；登录后，账号、订阅、虚拟资产、
旅行进度和跨设备内容由后端同步并校验。

## 开始开发

客户端需要 macOS、Xcode 26+ 和
[XcodeGen](https://github.com/yonaskolb/XcodeGen)：

```bash
Scripts/bootstrap-worktree.sh
Scripts/build.sh
Scripts/test.sh
Scripts/run.sh
```

脚本会从 `project.yml` 生成本地 `LingoTrip.xcodeproj`。不要提交生成的工程或 `build/`，
也不要在 `Packages/LingoKit` 中直接运行 `swift build`。多工作树可以并行写代码，但所有
Xcode 构建、测试、归档和模拟器安装会通过仓库级锁自动排队，避免争抢 CPU、内存、磁盘
和同一台模拟器。每个工作树使用自己的 DerivedData，Swift Package 下载缓存则安全共享。

对话提示词、回复分条等纯逻辑改动优先运行 `Scripts/test-conversation.sh`；它不构建宿主 App
和 SpeechKit，通常远快于完整测试。提交前再按改动风险运行 `Scripts/test.sh`，完成后用
`Scripts/run.sh` 一次性构建、安装并启动模拟器。需要固定模拟器时设置
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
Scripts/                客户端构建与测试入口
tools/                  离线数据处理工具
docs/                   架构、产品与按需运维说明
project.yml             Xcode 工程配置的唯一事实源
```

客户端模块的直接依赖以
[`Packages/LingoKit/Package.swift`](Packages/LingoKit/Package.swift) 为准：

```text
App 组合根
├── Feature：Auth / Home / Chat / Onboarding / Story / Roster / Map /
│            Favorites / Settings
├── 领域与集成：DomainKit / StoryEngine / SyncKit
├── 服务：BackendKit / BillingKit / LLMKit / MediaKit / SpeechKit /
│        DictKit / PersistenceKit
└── 基础：CoreKit / DesignSystem
```

Feature 之间不直接依赖。跨页面导航和服务选择在 `App/RootView.swift` 与
`App/AppEnvironment.swift` 中完成。

## 数据边界

- 游客使用本地领域服务，离线也能完成主要体验。
- 登录用户的资产、权益和进度由服务端权威接口处理。
- SwiftData 只保留当前开发基线，负责本地投影、内容 Outbox 和语音上传队列。
- AI 请求统一经过后端；客户端不保存模型供应商密钥。
- 用户内容采用稳定 ID 和版本号同步，语音二进制存入私有对象存储。

## 轻量开发约定

- 一个逻辑工作一个提交，不把无关修改混入同一提交。
- 新增 Swift 文件或模块依赖后运行 `Scripts/test.sh`。
- 正式发布前 SwiftData 可直接更新基线并重置测试数据；有真实用户后再引入版本迁移。
- 跨 actor 传递 `Sendable` DTO，不把 SwiftData 实体带出仓库 actor。
- 文档只记录稳定边界、设计意图和操作入口；完成的计划与阶段快照不长期保留。

更多说明见 [`docs/README.md`](docs/README.md)。日常开发通常只需阅读本文件和对应模块代码。
