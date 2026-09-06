# 按任务选择开发入口与验证

这是按需速查表，不是每次修改前的必读清单。选择能证明本次行为正确的最小验证；已通过后，
只有新修改、失败或未解决的风险才需要追加检查。历史校准记录和阶段验收不构成日常提交门禁。

## 查找入口

| 任务 | 入口 |
| --- | --- |
| 启动、依赖、导航 | `App/LingoTripApp.swift`、`App/AppEnvironment.swift`、`App/RootView.swift` |
| 聊天与提示词 | `ChatFeature/ChatView.swift`、`ChatViewModel.swift`；对话规则在 `DomainKit/Conversation` |
| 本地存储与同步 | `PersistenceKit/Schema`、对应 Store；跨端契约在 `SyncKit` 和后端 content/sync 模块 |
| 语音 | `SpeechKit`、`RealtimeVoiceKit`；生命周期约束见 `realtime-voice.md` |
| 城市和剧情 | `App/Resources/regions.json`、对应剧情 JSON；逻辑在 `DomainKit`、`StoryEngine` |
| 后端接口 | `Backend/src/modules/<module>/routes.ts` → service → repository，按需要往下读 |
| 后端配置和数据库 | `Backend/src/config/env.ts`、模块 schema；共享身份在 `db/user-schema.ts` |
| 图片和离线工具 | 对应资产清单、`Tools/README.md` 或工具目录 README |

Swift 模块路径相对于 `Packages/LingoKit/Sources/`。需要符号地图时用
`Scripts/code-map.sh ChatFeature` 或 `Scripts/code-map.sh backend:auth`，不必先读全库。

## 验证选择

| 变化 | 通常足够的验证 |
| --- | --- |
| 文档、说明 | 检查差异、链接和命令准确性；不构建 App 或启动数据库 |
| 纯视觉调整 | 相关页面构建与观察；无需新增复刻布局实现的单元测试 |
| Swift 业务逻辑 | `Scripts/test.sh -only-testing:LingoTripTests/<Suite>` |
| 对话纯逻辑 | `Scripts/test-conversation.sh`，可继续传 `-only-testing:...` |
| 关系模型 | `Scripts/test-relationship.sh`，默认一轮；保留数值不变量和反例测试 |
| Swift 依赖边界 | `Scripts/check-architecture.sh --ios`；目标/资源变化另做相关构建 |
| 后端局部逻辑 | 在 Backend 执行 `pnpm exec vitest run test/<相关文件>`；类型契约变化加 `pnpm typecheck` |
| 后端模块依赖 | 在 Backend 执行 `pnpm architecture`，或根目录 `Scripts/check-architecture.sh --backend` |
| 数据库、事务、同步协议 | 配置隔离测试服务，执行受影响集成用例；不要指向生产数据库 |
| 跨模块重构、发布候选 | 按影响选择 `Scripts/test.sh` 或后端 `pnpm check`；发布再运行对应构建/部署检查 |

`Scripts/check-architecture.sh` 默认 `--ios`，不需要 Node/pnpm；`--all` 显式检查两端。
源文件长度、临时命名风格和文档里的 Target 数字不再作为硬门禁；依赖边界和大小写路径冲突仍检查。

后端 `pnpm check` 是 lint、typecheck、architecture、默认测试的组合，适合 CI/较大改动；
不必再逐项重跑其子命令。`pnpm build` 验证产物，按发布需要使用。
一次 `Scripts/test.sh` 已构建宿主，不必为同一模拟器再调用 `Scripts/build.sh`。
需要安装/启动时用相应运行流程；真机或 Release 属于不同构建目标。

功能大检查与跨模块流程参考 [验证矩阵](system-verification.md)。
`python3 Scripts/verify-backend-workflows.py` 为数据库/HTTP 流程创建独立本地服务并记录结果，
`Scripts/test-ui.sh -only-testing:LingoTripUITests/<Suite>/<test>` 运行指定 UI 路径。
二者均按需执行，不追加到每次修改的默认门禁。

## 重测和专项

- 关系压力测试的 10,000 个输入使用固定种子。一轮通过即可；排查时序不稳定才显式设置
  `RELATIONSHIP_TEST_PASSES=3`，重跑相同种子不等于增加输入覆盖。
- 关系持久化/同步/提示词同时变化时增加对应套件；只有影响广泛或发布验收时才跑全量，
  不再把“专项后全量 + 后端 + Release”当固定序列。
- 本地单元测试使用 mocks/内存夹具，可直接运行、修复与复测。集成/E2E 需要隔离的
  PostgreSQL/Redis，部分媒体测试还需 MinIO；现有 `RUN_*` 开关仍需显式开启。
- 线上 AI 评测使用生产网关、会消耗额度，仅在对应评测任务中启用。三个 Swift Live 套件
  默认标记为跳过，不计入通过数量。普通 CI 不运行线上评测或生产就绪探测。
- 图库覆盖实验、Blender 拟合和词典审校只在对应资产任务运行。已验收且哈希不变的资产可复用
  原审核；改图后复核新字节，发布保留完整性、许可、路径与永久身份约束。
- iOS 脚本已有模型校验缓存和构建锁，轻量对话测试不读取语音模型。遇到源码接口存在但
  编译器读取旧模块时，可换独立 `LINGOTRIP_DERIVED_DATA_PATH` 重试一次，不要每次都清空缓存。
