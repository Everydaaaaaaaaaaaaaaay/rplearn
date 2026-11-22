# 开发速查

按需查命令和入口，不是开工清单。什么时候验证、验证到什么程度，以 [AGENTS.md](../AGENTS.md) 的“验证：够用即停”为准。
学习、测评和挑战的专项入口见[学习功能开发入口](learning-program/dev-entries.md)，赴约测试见
[赴约接入记录](appointments-implementation-2026-11-01.md#测试入口)。

## 预览构建

```bash
Scripts/preview.sh build <页面>    # 源码改动后：重新生成工程、增量构建、安装并免登录启动
Scripts/preview.sh preview <页面>  # 已有最新构建：只安装和启动（不检查源码新旧）
Scripts/preview.sh status          # 查看 Xcode、设备与产物
```

可选页面：

- 常用：`messages`（默认）、`contacts`、`home`（活动首页）、`map`、`me`、`settings`、`subscription`
- 活动与赴约：`places-preview`、`world-preview`、`scenes-preview`、`appointments-preview`
- 学习：`learning`、`learning-test`、`role-learning`、`unit-challenge`、`practice-preview`、`achievement-preview`、`promotion-preview`
- 设计：`mascots-preview`（咕咕、嘎嘎全部姿势与小尺寸；前面加 `SIMCTL_CHILD_UI_TEST_MASCOT_ZOOM=gugu` 或 `=gaga` 放大单只）

说明：

- `build` 会先按 `project.yml` 重新生成工程，新增 Swift 文件会自动加入编译。生成的工程文件不提交。
- 产物固定在 `build/DerivedData/Build/Products/Debug-iphonesimulator/LingoTrip.app`，可用 `LINGOTRIP_DERIVED_DATA_PATH` 覆盖。
- 设备优先使用工作树绑定的；未绑定时选最新 iOS 运行时里的 iPhone，同一运行时优先复用已启动的设备。
  可用 `LINGOTRIP_SIMULATOR_UDID` 指定。脚本不创建克隆，不关闭其他项目的设备，也会自动选择完整 Xcode，不需要改 `xcode-select`。
- 模拟器窗口在 Device Hub：Xcode → Open Developer Tool → Device Hub，选择脚本输出的设备。

### 查看页面

优先用 Computer Use 点一遍受影响的页面。没有 Computer Use，或 Device Hub 连接超时（2026-09-14 实测出现过 `timeoutReached`），
就截一张图确认首屏，交互留给用户看，不要反复换名称重试：

```bash
xcrun simctl io <设备UDID> screenshot <输出路径>.png
```

- 首屏是异步加载的，刚启动截到空背景时稍等再截，不要因此重建。
- 点底部标签前先收起键盘，避免点到键盘区域。

### 免登录预览

`preview.sh` 在 Debug 下通过 `SIMCTL_CHILD_` 传入 `UI_TEST_SKIP_ONBOARDING=1`、`UI_TEST_REQUIRE_AUTHENTICATION=0`、
`UI_TEST_DISABLE_BACKGROUND_REFRESH=1`，后端固定为 `http://127.0.0.1:9`。未登录时 `RootView` 调用
`AppEnvironment.activateUITestWorkspace()`，使用内存数据和本地角色，重启后重置。

- 已有真实登录态不会被替换；不要为了制造测试条件清空钥匙串或数据库。
- 只能预览页面，不能验证真实登录、在线 AI 或同步。Release 不含这个入口。
- 跨进程断点测试可设 `UI_TEST_PERSISTENCE_NAMESPACE=<新 UUID>`，使用独立的临时 SwiftData 存储，只有同一 UUID 的重启会复用。
  `LondonEpisodeTests/testReadingRouteAndResume` 用这个入口，并等选择后的下一页出现、确认断点已保存后再终止进程。
- 会员订阅页的完整价格排版：`SIMCTL_CHILD_UI_TEST_SUBSCRIPTION_PRICES=1 Scripts/preview.sh preview subscription`。
  这个 Debug 夹具标明“示例价格，不可购买”，不改变 StoreKit 商品、生产价格或权益；正常预览缺少商店价格时显示重新加载并禁用购买。

### 活动与城市预览

- `places-preview`：伦敦三地点样板。咖啡馆有 Alex 的七节点四结尾故事，书店和公园是独处短篇，画面是程序化卡通地点。
  只在免登录内存账号里注入本机外出服务，不调用正式分配或好友接口；外出记录存在 `debug.place-outing.preview.v1.manual`
  命名空间，重启后继续。这是界面与状态机样板，不代表十五城内容已发布。正式入口由 `activity-world-release.json` 控制。
  `CityPlaceOutingTests` 定向检查实际分支、暂停返回、杀进程恢复、足迹，以及最大辅助字号下的独处结尾。
- `world-preview`：十五城完整离线游玩，用 `UI_TEST_SCENE_CITY` 指定城市。
- `scenes-preview`：十五城地点浏览。点顶部城市名切换城市，左右滑动或点两侧箭头切换地点。
- `appointments-preview`：赴约约定页，见[赴约测试入口](appointments-implementation-2026-11-01.md#测试入口)。

### iOS 图片分包

地图、城市活动和剧情共用静态图片目录，文件名包含内容 SHA256。首次读取时核对大小和指纹，同一文件的并发请求会合并，
已下载的图片优先读本机。缓存上限 220 MiB，被系统清理后可重新下载。伦敦、墨尔本、纽约的图片和首个主线美术、离线词典、
朗读模型、剧情文本和预制配音随包提供。

```sh
python3 Tools/ContentPipeline/ios-content-packs.py --output build/ios-content-public
python3 -m http.server 18765 --bind 127.0.0.1 --directory build/ios-content-public
LINGOTRIP_CONTENT_ASSET_BASE_URL=http://127.0.0.1:18765 Scripts/preview.sh build world-preview
```

- 选中地图城市时预取第一张活动图片和活动页背景；剧情目录预取当前可读章节的首幕，阅读时预取下一幕。
  城市页面先显示同一地点的低分辨率预览，再加载全分辨率图。
- 发布时把导出文件放到公开、不可变的 HTTPS 静态目录，用同一地址设置 `LINGOTRIP_CONTENT_ASSET_BASE_URL` 执行 `Scripts/archive.sh`。
  内容更新只新增文件，保留已发布 App 仍在引用的旧文件。变量留空时构建全量资源版。
- 修改城市摄影后，先用 Google `cwebp` 和 `python3 Tools/ContentPipeline/encode-city-display-images.py` 重新生成同分辨率显示文件，
  再用 `python3 Tools/ContentPipeline/ios-content-packs.py --update` 更新指纹和预览图。逐图选档与像素对照见
  [城市编码验收](verification/ios-city-webp-2026-11-20.md)。

## 查找入口

| 任务 | 入口 |
| --- | --- |
| 启动、依赖、导航 | `App/LingoTripApp.swift`、`App/AppEnvironment.swift`、`App/RootView.swift` |
| 聊天与提示词 | `ChatFeature/ChatView.swift`、`ChatViewModel.swift`；对话规则在 `DomainKit/Conversation` |
| 本地存储与同步 | `PersistenceKit/Schema`、对应 Store；跨端契约在 `SyncKit` 和后端 content/sync 模块 |
| 语音 | `SpeechKit`、`RealtimeVoiceKit`；生命周期约束见 `realtime-voice.md` |
| 城市和剧情 | `App/Resources/regions.json`、对应剧情 JSON；逻辑在 `DomainKit`、`StoryEngine` |
| 界面组件 | `DesignSystem/Puff/`；规范见 [设计系统](design-system.md) |
| 后端接口 | `Backend/src/modules/<module>/routes.ts` → service → repository，按需要往下读 |
| 后端配置和数据库 | `Backend/src/config/env.ts`、模块 schema；共享身份在 `db/user-schema.ts` |
| 图片和离线工具 | 对应资产清单、`Tools/README.md` 或工具目录 README |

Swift 模块路径相对于 `Packages/LingoKit/Sources/`。需要符号地图时用 `Scripts/code-map.sh ChatFeature` 或
`Scripts/code-map.sh backend:auth`，不必先读全库。

## 验证命令

只在 AGENTS.md 规定需要时使用；每类选最相关的一条。

| 对象 | 命令 |
| --- | --- |
| Swift 单测 | `Scripts/test.sh -only-testing:LingoTripTests/<Suite>`（已构建测试宿主，不必再跑 `Scripts/build.sh`） |
| 对话纯逻辑 | `Scripts/test-conversation.sh`，可继续传 `-only-testing:...` |
| 关系模型 | `Scripts/test-relationship.sh`，一轮即可 |
| UI 路径 | `Scripts/test-ui.sh -only-testing:LingoTripUITests/<Suite>/<test>` |
| Swift 依赖边界 | `Scripts/check-architecture.sh`（默认 `--ios`，不需要 Node；`--all` 两端都查） |
| 后端局部逻辑 | 在 Backend 执行 `pnpm exec vitest run test/<相关文件>`；类型契约变化加 `pnpm typecheck` |
| 后端模块依赖 | 在 Backend 执行 `pnpm architecture` |
| 后端较大改动 | `pnpm check`（lint、typecheck、architecture、默认测试的组合，不必再逐项重跑） |
| 数据库与 HTTP 流程 | `python3 Scripts/verify-backend-workflows.py`，自动创建独立的本地服务 |

- 源文件长度、命名风格和文档里的 Target 数量不是门禁；依赖边界和大小写路径冲突仍会检查。
- UI 测试单条默认 300 秒超时，超时即判失败，避免模拟器异常时整批挂起；长流程用 `LINGOTRIP_UI_TEST_TIMEOUT=<秒>` 放宽。
- UI 测试失败时先读 xcresult 里的实际断言位置；诊断收集阶段的 `simctl` 错误不等于根因。
  隐藏的首页可能仍在辅助功能树里，判断是否回到首页要看入口可点击，或二级页面的返回按钮是否消失。
- 关系压力测试的 10,000 个输入使用固定种子，排查时序不稳定才设 `RELATIONSHIP_TEST_PASSES=3`；重跑相同种子不增加覆盖。
- 本地单测使用 mock 和内存夹具。集成、E2E 需要隔离的 PostgreSQL/Redis，部分媒体测试还需要 MinIO，相应 `RUN_*` 开关需显式开启。
  Swift Live 套件默认跳过，跳过项不计入通过数。
- 功能大检查和跨模块流程参考[验证矩阵](system-verification.md)；发布流程见[后端发布文档](backend/DEPLOYMENT.md#发布)。
- 图库覆盖实验、Blender 拟合和词典审校只在对应资产任务里运行。已验收且哈希不变的资产复用原审核。

## 常见问题

- **新增文件后报 `Cannot find ... in scope`**：先确认定义文件存在，再运行 `Scripts/preview.sh build <页面>` 重新生成工程。
  不要删除调用或复制定义来绕过。
- **改了公共类型后运行时崩溃**：给 DesignSystem 等底层模块的公共类型增删存储属性后，增量构建可能不重编依赖它的 Feature 模块，
  运行时在 `initializeWithCopy` 一类位置 `EXC_BAD_ACCESS`。删除
  `build/DerivedData/Build/Intermediates.noindex/LingoKit.build/Debug-iphonesimulator/` 下该模块和依赖它的 `<模块>-t.build`
  目录后重新构建。若是编译期读到旧模块接口，可换独立的 `LINGOTRIP_DERIVED_DATA_PATH` 重试一次。不要每次都清空缓存。
- **磁盘空间不足**：构建报 “out of space”，或应用一启动就因 `dyld: Library not loaded` 崩溃，先检查系统盘剩余空间，
  清理自己产生的录屏、结果包等临时文件。模拟器每次安装都会为语音模型新编一份约 230 MB 的 Core ML 缓存，
  `preview.sh` 和测试脚本会在安装前自动清掉旧的；绕过脚本直接安装时，旧缓存在 App 数据容器的
  `Library/Caches/<Bundle ID>/com.apple.e5rt.e5bundlecache`。
- **预览题型或页面和请求不一致**：用 `xcrun simctl getenv <设备UDID> <变量名>` 检查全局残留的环境变量，残留值会覆盖启动环境。
  停掉测试后重启该模拟器即可清除；不要靠卸载 App、清空账号或改业务逻辑掩盖。
- **启动慢**：测量口径、缓存启动策略和复测命令见[启动性能记录](launch-performance.md)。
