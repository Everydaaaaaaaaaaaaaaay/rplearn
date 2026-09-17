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
- 线上 AI 评测使用生产网关、会消耗额度，仅在对应评测任务中启用。Swift Live 套件
  默认标记为跳过，不计入通过数量。普通 CI 不运行线上评测或生产就绪探测。
- 图库覆盖实验、Blender 拟合和词典审校只在对应资产任务运行。已验收且哈希不变的资产可复用
  原审核；改图后复核新字节，发布保留完整性、许可、路径与永久身份约束。
- iOS 脚本已有模型校验缓存和构建锁，轻量对话测试不读取语音模型。遇到源码接口存在但
  编译器读取旧模块时，可换独立 `LINGOTRIP_DERIVED_DATA_PATH` 重试一次，不要每次都清空缓存。

## Device Hub 与免登录预览

参考 ClassMind 的 `run-classmind` 驱动：固定构建目录、复用模拟器、读取产物 Bundle ID、
重启 App 使启动参数生效。LingoTrip 使用现有 Debug 内存账号，不复制 ClassMind 的 onboarding defaults。

```bash
Scripts/preview.sh status                 # 确认 Xcode、设备与产物
Scripts/preview.sh build home             # 源码改变后：增量构建、安装、免登录启动
Scripts/preview.sh preview home           # 已构建/测试后：只安装和启动
```

若新增 Swift 文件后在 Xcode 中出现 `Cannot find ... in scope`（例如 `seedMarketingCapture`），
先确认定义文件存在，再运行 `Scripts/preview.sh build home`。该命令会先用 `project.yml`
重新生成工程，补齐新增文件的编译成员，再构建安装。只更新源码而未重新生成 `.xcodeproj`
会造成此类报错；不要删除调用或复制定义来绕过，生成的工程文件不提交。

页面可选 `messages`、`contacts`、`home`（活动首页）、`map`、`me`、`subscription`（会员订阅）、`learning`（英语旅程）、`review`（仅 Debug 的短复习内存预览）。产物固定取
`build/DerivedData/Build/Products/Debug-iphonesimulator/LingoTrip.app`，可通过既有
`LINGOTRIP_DERIVED_DATA_PATH` 覆盖；`preview` 不检查源码新旧，尚未构建的修改应使用 `build`。
脚本自动选择完整 Xcode，无需修改系统 `xcode-select`。设备按既有工作树配置或已启动 iPhone 选择，
可用 `LINGOTRIP_SIMULATOR_UDID` 显式指定；不创建 Clone，不关闭其他项目的设备。

免登录参数通过 `SIMCTL_CHILD_` 传入：`UI_TEST_SKIP_ONBOARDING=1`、
`UI_TEST_REQUIRE_AUTHENTICATION=0`、`UI_TEST_DISABLE_BACKGROUND_REFRESH=1`，后端固定
`http://127.0.0.1:9`。在 Debug 且未登录时，`RootView` 调用
`AppEnvironment.activateUITestWorkspace()`，使用内存数据和本地角色；重启后测试数据重置。
若已有真实登录态，不会强行替换账号；不要清空钥匙串或数据库来制造测试条件。
此方式只用于页面预览，不能验证真实登录、在线 AI 或同步。Release 不支持该入口。

Xcode 27 的模拟器窗口由 **Device Hub** 提供，应用标识 `com.apple.dt.Devices`；本机路径为
`/Volumes/data/Applications/Xcode.app/Contents/Applications/DeviceHub.app`。
从 Xcode → Open Developer Tool → Device Hub 打开并选择脚本输出的设备。
[Apple 官方说明](https://developer.apple.com/documentation/xcode/device-hub)
与[设备管理入口](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac)。
旧 `Contents/Developer/Applications/Simulator.app` 路径在此 Xcode 安装中不存在。

完成 iOS 工作后，安装当前源码的最新构建并留在目标页面供用户查看。优先用 Computer Use
短流程验证受影响交互；无需默认跑整套 UI 测试或反复构建。
2026-09-14 实测：Computer Use 可读取 Xcode，但 Device Hub 连接返回 `timeoutReached`，
从 Xcode 菜单打开后仍未解决；不能将此限制解释为 App 失败。遇到同样问题不要循环换名称重试，
可用下列只读截图确认首屏，但应明确未完成 Computer Use 交互验证：

```bash
DEVELOPER_DIR=/Volumes/data/Applications/Xcode.app/Contents/Developer \
  xcrun simctl io <脚本输出的设备UDID> screenshot /tmp/lingotrip-preview.png
```

首屏是异步加载的；刚启动立即截图可能只有背景，应待页面加载后再截一次，不因此重建 App。
点击底部 Tab 前先收起键盘，避免点击落在键盘区域。隐藏的首页仍可能存在于辅助功能树，
使用入口可点击性或二级页面返回按钮消失判断是否返回首页。测试失败时先读 xcresult 的实际
断言位置；诊断收集阶段的 `simctl` 错误不等于测试根因。

会员订阅页的完整价格排版可用
`SIMCTL_CHILD_UI_TEST_SUBSCRIPTION_PRICES=1 Scripts/preview.sh preview subscription` 查看。
该 Debug 专用夹具明确显示“示例价格，不可购买”，不改变 StoreKit 商品、生产价格或权益。
正常预览不设置该变量，缺少商店价格时显示重新加载入口并禁用购买。

## 启动速度与偶发慢启动

测量口径、缓存启动策略和定向复测命令见 [启动性能记录](launch-performance.md)。
