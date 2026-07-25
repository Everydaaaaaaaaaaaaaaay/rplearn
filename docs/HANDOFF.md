# LingoTrip 项目交接文档

> 面向接手的开发者：读完本文你应能独立构建、运行、扩展本项目。
> 配套文档：`docs/plan.md`（原始开发计划与技术决策，本文是它落地后的现状快照）。
> 最后更新：2026-07-26（M0/M1/M2 + UI 全面重构完成，全量测试通过）。

---

## 1. 这是什么

**LingoTrip** 是一款 iOS 原生（Swift / SwiftUI）外语学习 App。核心玩法：用户以「到世界各地旅行」为叙事框架，与不同国籍、身份、性格的 **AI 角色**用英语聊天，在真实语境中学习。v1 只做英语。

主要能力：

- **聊天模块**：文本 / emoji / 语音消息；点词查词（本地 ECDICT 词典 + 浮窗）、整句翻译、TTS 朗读、消息收藏；后台「教练 AI」并行纠错；到一定轮次插入语境小测（quiz）；语音消息附口语点评。
- **会话与记忆**：分层记忆（short→mid→long）按订阅配额压缩注入，长对话不爆上下文。
- **AVG 剧情模块**：竖屏视觉小说，3 位主角色各有主线章节。
- **角色系统**：3 位手工设计主角色（伦敦 / 墨尔本 / 纽约）+ AI 随机生成的「偶遇」角色；好友位机制。
- **地区 / 机票 / 票根**：地图前往新城市，机票消耗生成收藏级票根。
- **经济系统**：金币 + 订阅（本地模拟，支付网关占位）。
- **首启引导**：以聊天皮肤演出的开场剧情 → 选主角色 → 引导主线。

---

## 2. 快速开始

**前置**：macOS + Xcode（开发时用 26.1.1）+ [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

```bash
# 构建（自动 xcodegen generate + xcodebuild，跑模拟器）
Scripts/build.sh

# 跑全部测试
Scripts/test.sh
```

两个脚本**每次都会先跑 `xcodegen generate`**，因为 `.xcodeproj` 不入库、由 `project.yml` 生成，新增源文件必须重新生成工程才能进入编译。

**在 Xcode.app 里开发**：先 `xcodegen generate`，再打开生成的 `LingoTrip.xcodeproj`。⚠️ 不要在 `Packages/LingoKit/` 里跑 `swift build`——它会留下 macOS 的 `.build/` 与 `.swiftpm/` 残留，污染 Xcode 的包解析（曾导致「Missing package product」全线报错）。这两个目录已在 `.gitignore` 中。若 Xcode 仍报包加载失败：**File → Packages → Reset Package Caches**，再 **Clean Build Folder（⇧⌘K）**。

---

## 3. 工程结构与架构

### 3.1 单一本地包 + XcodeGen

- `project.yml` 是工程的**唯一事实来源**，`.xcodeproj` 由它生成、**不入 git**。
- 所有业务代码放在**一个本地 Swift Package `Packages/LingoKit`**，内部拆成多个 library target。
- App 壳 `App/`（`LingoTripApp` / `RootView` / `AppEnvironment`）只负责组合根接线与 SwiftUI 入口。
- 资源（词典 sqlite、角色 / 地区 / 剧情 JSON、App 图标）在 `App/Resources` 与 `App/Assets.xcassets`，随 App 打包，用 `Bundle.main` 读取。
- 较大的 Module 在 target 内按领域职责继续分目录；子目录不产生新 target 或依赖 seam。当前重点分组为 `DomainKit/{Conversation,Progression,Story,World}`、`LLMKit/{Contracts,Models,Providers,Routing,Settings,StructuredOutput,Transport}` 与 `PersistenceKit/{Contracts,Schema,Stores}`。

### 3.2 严格分层依赖图

依赖方向**只能向下**，Feature 之间**零依赖**（跨 Feature 的跳转由组合根用闭包 / `AnyView` 注入）：

```
App（组合根 AppEnvironment / RootView）
  └─ Feature 层：ChatFeature / HomeFeature / MapFeature / StoryFeature /
                 OnboardingFeature / SettingsFeature / FavoritesFeature / RosterFeature
       └─ Domain 层：DomainKit（业务服务）/ StoryEngine（剧情 DSL 与播放器）
            └─ Service 层：LLMKit / SpeechKit / DictKit / PersistenceKit
                 └─ Infra 层：CoreKit / DesignSystem
```

规则在 `Packages/LingoKit/Package.swift` 里用 `feature(_:extraDependencies:)` 辅助函数统一声明，一眼可查每个 Feature 的依赖。DictKit 因附带词典卡 UI，额外依赖 DesignSystem（层级仍向下）。

### 3.3 关键工程约定

- **Swift 6 严格并发**：所有写库操作收敛到 `@ModelActor` 仓库；跨 actor 只传 `Sendable` DTO；视图模型 `@MainActor @Observable`。
- **UI 只读库**：SwiftUI 用 DTO / `@State`，不直接持有 `@Model` 实体跨线程。
- **Prompt 集中管理**：所有 LLM prompt 收敛在 `DomainKit/Conversation/PromptBuilder.swift`（角色扮演）与各 Module 内，便于迭代与 snapshot 测试锁定。
- **密钥只进钥匙串**：API Key 存 `CoreKit/KeychainStore`，绝不落 prompt / 日志。
- **测试框架用 Swift Testing**（`@Test` / `#expect`），不是 XCTest。

### 3.4 UI 信息架构与视觉约定

根视图是四个独立 `NavigationStack` 的原生 `TabView`；每栏都通过 `.tabItem` 注册给系统，保留原生切换、导航状态、安全区、键盘与辅助功能行为，仅用 DesignSystem tint 统一品牌色：

```
首页（城市 Hub → 主线剧情 / 城市活动 / 聊天）
地图（MapKit 3D → 城市卡 / 飞行转场 / 票根夹）
消息（会话列表 → 好友 / 角色资料 / 聊天）
我的（资料 / 订阅 → 收藏 / 设置）
```

- 深层页面用 `.dsTabBarHidden()` 映射到系统 `.toolbar(.hidden, for: .tabBar)`；返回时由系统自动恢复。
- 视觉唯一事实源在 `DesignSystem/Tokens`：`DSColor`、`DSLayout`、`DSAnimation`、`DSScenePalette`；页面不要新增硬编码品牌色与混用圆角。透明材质统一用 `.dsMaterial(_:in:)`，开启“降低透明度”时会自动降级为不透明 surface。
- 首页已接入 `city_backdrop_london`、`city_backdrop_melbourne`、`city_backdrop_newyork` 三张正式生成式背景；`CityBackdropView` 在未知城市或素材缺失时仍以多层城市剪影和云动画兜底。首页内容在城市栏下保留自适应景观窗口，深色模式会压低素材亮度与饱和度。
- 首页两个核心入口按城市加载 `home_mainline_<regionID>` 与 `home_activity_<regionID>` 横幅美术；当前三城共 6 张正式素材。左侧只使用单一品牌实色与短透明度过渡，缺图时 `ExploreCard` 自动退回品牌实色与 SF Symbol，不影响导航和可访问性。
- `AccentColor.colorset` 与 `Color.dsSky` 手工保持一致；根视图统一 `.fontDesign(.rounded)` 与 `.tint(.dsSky)`。
- 会话已读/置顶用 UserDefaults 轻量状态，不改 SwiftData schema；聊天页进入即标记已读。

---

## 4. 模块详解

### Infra 层

| 模块 | 职责 | 关键文件 |
|---|---|---|
| **CoreKit** | 日志、错误、钥匙串、token 估算、分词、音频会话协调（录/放互斥的 actor） | `Log` `AppError` `KeychainStore` `TokenEstimator` `WordTokenizer` `AudioSessionCoordinator` |
| **DesignSystem** | 动态色板、布局/动画/场景 token、3D 按钮、卡片、头像、Chip、批注卡、庆祝粒子、原生 Tab 可见性桥接、气泡与触觉 | `Tokens/` `Styles/` `Components/` `MessageBubbleView` `TappableText` `Haptics` |

### Service 层

| 模块 | 职责 | 关键文件 |
|---|---|---|
| **LLMKit** | 多供应商 LLM 抽象：Anthropic / OpenAI / OpenAI 兼容；SSE 流式；json_schema 结构化输出；分档路由与重试；钥匙串密钥 | `LLMRouter` `AnthropicProvider` `OpenAIProvider` `SSEParser` `JSONExtractor` `LLMRequest` `LLMTier` `LLMSettingsStore` |
| **SpeechKit** | Apple TTS（`AVSpeechSynthesizer`）、语音识别（`SFSpeechRecognizer`）、录制与语音消息存储、口音映射 | （见 `SpeechService` / `VoiceRecorder` / `VoiceMessagePlayer`） |
| **DictKit** | ECDICT 预处理为 sqlite（只读、原生 sqlite3）、词形还原、语法点库；附词典卡 UI 与查词浮窗 | `DictDatabase` `WordFormRules` `GrammarPointStore` `DictCardView` `WordLookupOverlay` |
| **PersistenceKit** | SwiftData `SchemaV1`、领域枚举、DTO、`@ModelActor` 仓库全家桶、迁移计划占位 | `SchemaV1` `DomainEnums` `DTOs` + 各 Store |

### Domain 层

| 模块 | 职责 | 关键文件 |
|---|---|---|
| **DomainKit** | 全部业务服务 | 见下 |
| **StoryEngine** | 剧情 JSON DSL、静态校验、`StoryPlayer`（无 UI 依赖的 `@Observable` 播放器） | `StoryScript` `StoryPlayer` |

DomainKit 服务清单：

- `PromptBuilder`：角色扮演 system prompt（按学制分级的语言约束、口语化风格、主线引导、记忆注入、出题指令）、历史窗口裁剪。
- `CoachService`：教练纠错（`review`）+ 口语点评（`reviewSpeech`），fast 档 / JSON / 超时静默放弃。
- `MemoryService`：分层记忆压缩（short→mid→long 级联）、按订阅配额裁剪、注入段落。
- `EconomyService`：金币 / 订阅（`PurchaseGateway` 占位）、道具定价、记忆配额（`MemoryQuota`）。
- `EncounterService`：偶遇概率与来源掷骰（纯函数可测）、LLM 结构化生成角色卡（重试 + 本地模板兜底）。
- `TravelService`：机票可用性判定与出行、票根生成。
- `QuizService`：出题触发判定、prompt 指令、`<quiz>` 截取解析、本地判分。
- `KeywordAnnotator`：本地词频给角色回复关键词划线。
- `TranslationService`：整句翻译（结果缓存）。
- `RegionCatalog` / `MainlineCatalog` / `SeedData`：地区、主线章节目录、内置角色种子数据。

### Feature 层

| 模块 | 页面 | 关键点 |
|---|---|---|
| **ChatFeature** | 消息列表 + 聊天页 | QQ 式搜索/未读/置顶/滑动已读；聊天流式链路、统一批注卡、quiz 庆祝/错误反馈、语音条、Apple 端上翻译兜底 |
| **HomeFeature** | 首页聚合 Hub + 主线/活动二级页 | 城市动态剪影背景、最近会话、两张探索入口；`MainlineListView` / `ActivitiesView` |
| **MapFeature** | MapKit 3D 地图 + 飞行转场 + 票根夹 | realistic elevation 相机、三态 Pin、城市卡、购票/出行、`FlightTransitionOverlay`、6 套动态票根色 |
| **StoryFeature** | AVG 剧情 | 竖屏 ZStack、打字机台词、动态深浅场景色、Duo 选项 |
| **OnboardingFeature** | 首启引导 | 聊天剧情内角色资料卡 + 3D 横滑实体选角卡 |
| **SettingsFeature** | 我的 + 设置 | `MyPageView` 聚合资料/订阅/收藏/设置；二级设置保留 AI、模型、语音、学习开关 |
| **FavoritesFeature** | 收藏夹 | 收藏语句翻阅、句内查词、朗读 |
| **RosterFeature** | 好友与角色资料 | 好友位、伙伴/偶遇分区、角色全字段资料卡、发消息入口 |

---

## 5. 数据模型（SchemaV1）

定义在 `PersistenceKit/Schema/SchemaV1.swift`，`VersionedSchema` + `LingoMigrationPlan`（迁移占位，新增 SchemaV2 时补 stage）。10 个实体：

| 实体 | 说明 |
|---|---|
| `UserProfileEntity` | 用户档案（单例行）：金币、订阅、好友位上限、当前地区、解锁地区、难度等级、出题总开关 |
| `CharacterEntity` | AI 角色，`cardJSON` 存原始角色卡供 prompt 复渲染；主角色 / 好友标记 |
| `ConversationEntity` | 会话：轮次、距上次出题轮次、出题退订、已压缩游标、偶遇 / 归档标记 |
| `MessageEntity` | 消息：角色 / 类型 / 文本 / 音频；关键词、教练、口语点评、quiz（含已答下标）、翻译等 JSON 附加信息 |
| `MemoryEntity` | 分层记忆条目（short / mid / long + 重要度） |
| `FavoriteEntity` | 收藏语句（弱引用消息） |
| `ItemEntity` | 道具（机票：通用 / 指定国家） |
| `TicketStubEntity` | 票根（serialNumber + artSeed 决定配色花纹） |
| `StoryProgressEntity` | 剧情进度（断点续播） |
| `QuizRecordEntity` | 出题记录（供统计） |

写操作全部经对应 `@ModelActor` 仓库（`ChatStore` / `RosterStore` / `EconomyStore` / `MemoryStore` / `ItemStore` / `TicketStubStore` / `StoryProgressStore` / `FavoritesStore`）；跨 actor 传 `DTOs.swift` 里的 `Sendable` 快照。

> 注意：`#Predicate` 在本工程里经常要写显式泛型 `#Predicate<Entity>` 帮助类型检查器。

---

## 6. 核心功能实现要点（含文件指路）

### 6.1 聊天主链路
`ChatViewModel.streamAssistantReply()`：注入记忆段落 + 按配额裁剪原文窗口 + 决定是否出题 → `PromptBuilder.roleplayRequest`（balanced / 流式 / temp 0.9）→ 边流式边落库 → 定稿后关键词标注、主线机票发放判定、后台触发记忆压缩。教练纠错与口语点评在旁路 `Task` 里并行，不阻塞主链路。

### 6.2 语境出题（quiz）
`QuizService` + `ChatViewModel` + `ChatView.quizCard`。触发条件：出题总开关 + 本会话未退订 + `turnsSinceQuiz` 达阈值（N=6±2）。命中则在角色回复 system 尾部追加出题指令，回复末尾输出 `<quiz>{...}</quiz>`，流式结束后截取解析（失败当普通文本静默放弃），渲染选项气泡、本地判分、答对奖励金币、写 `QuizRecordEntity`。

### 6.3 分层记忆
`MemoryService`。回复完成后后台检查：未压缩消息 ≥ 阈值或 token 超预算 → fast 档把最旧一批压成 short；short 超配额合并进 mid；mid 溢出提炼进 long（去重、用户稳定事实优先）；long 超配额按重要度裁剪。配额来自订阅（`EconomyService.memoryQuota`：Free 12/8/5、Plus 24/20/15、Pro 40/40/40）。注入分「长期了解」（long）+「近期发生」（short+mid）两段。DEBUG 下设置页有可视化调试面板。

### 6.4 教练与口语点评
`CoachService`：`review` 审核文本消息语法 / 用词，`reviewSpeech` 对语音转写做口语自然度点评（评分 + 中文点评 + 更自然说法建议）。均 fast 档 / JSON 结构化 / 15s 超时静默放弃，结果分别写 `coachReviewJSON` / `speechReviewJSON`。

### 6.5 偶遇
`EncounterService`：P(偶遇)=0.35，来源 60/30/10（当地人 / 本国其他地区 / 外国人）——判定为纯函数便于测试。命中后 balanced / temp 1.0 / JSON 生成角色卡，字段校验 + 姓名去重，失败重试 1 次再回退本地模板卡。未加好友只能当场聊，离开归档只读。

### 6.6 剧情引擎
`StoryEngine`：JSON DSL 节点类型 `line / choice / branch(flag) / reward / end`，加载时静态校验（next 可达、无悬空引用）。`StoryPlayer` 无 UI 依赖，reward / unlock 经回调交给经济 / 角色系统。**首启引导与 AVG 复用同一引擎、换渲染皮肤**（聊天气泡 vs 竖屏立绘）。剧情脚本在 `App/Resources/Stories/*.json`，目录见 `MainlineCatalog`。

### 6.7 LLM 抽象层（任务矩阵）
`LLMKit`。分三档：`fast`=haiku（纠错 / 翻译 / 记忆 / 口语点评）、`balanced`=sonnet（角色对话 / 偶遇生成）、`deep`=opus（最高质量）。`LLMRouter` 负责选供应商、重试与退避。⚠️ 新模型（sonnet-5 / opus-4.7+ / fable / mythos）拒绝采样参数，`AnthropicProvider.supportsSamplingParameters` 会自动丢弃 temperature。供应商 / Key / 模型可在设置页配置并测试连接。

---

## 7. 开发进度

计划见 `docs/plan.md`，里程碑（每单元 = 构建通过 + 一次 commit）**M0 / M1 / M2 全部完成**：

| 阶段 | 单元 | 状态 |
|---|---|---|
| M0 | 0.1 工程初始化 / 0.2 Package 骨架 / 0.3 测试基建 | ✅ |
| M1 | 1.1 LLMKit + 设置页 | ✅ |
| | 1.2 ECDICT 词典管线 | ✅ |
| | 1.3 SchemaV1 + 仓库 + 主角色导入 | ✅ |
| | 1.4 聊天核心 | ✅ |
| | 1.5 可点词渲染 | ✅ |
| | 1.6 消息四功能 + TTS + 翻译 + 收藏 | ✅ |
| | 1.7 教练 AI 并行审核 | ✅ |
| | 1.8 语音消息 | ✅ |
| | 1.9 记忆 v1（short） | ✅ |
| | 1.10 首启引导 | ✅ |
| M2 | 2.1 AVG 剧情模块 | ✅ |
| | 2.2 经济系统 | ✅ |
| | 2.3 地区 / 机票 / 票根 | ✅ |
| | 2.4 偶遇系统 | ✅ |
| | 2.5 语境出题 | ✅ |
| | 2.6 记忆完整版（mid/long + 配额 + 面板） | ✅ |
| | 2.7 打磨（图标 / 触觉 / 剧情补章 / 深色模式 / 空态） | ✅ |
| | 2.8 口语点评 | ✅ |
| UI | DesignSystem token / 样式 / 组件地基 | ✅ |
| | 四 Tab 信息架构、首页 Hub、MapKit 3D 与飞行转场 | ✅ |
| | 消息/好友/聊天/我的全面重构 | ✅ |
| | 首启选角、AVG、词典、收藏、票根长尾换肤 | ✅ |

当前为 16 个 Sources Module；测试由 App 托管的 `LingoTripTests` 统一执行。

---

## 8. 构建 / 测试 / 验证流程

```bash
Scripts/build.sh          # xcodegen + xcodebuild build（模拟器）
Scripts/test.sh           # xcodegen + xcodebuild test
# 详细用例计数（去掉 -quiet）：
xcodebuild -project LingoTrip.xcodeproj -scheme LingoTrip \
  -destination 'platform=iOS Simulator,id=<UDID>' -derivedDataPath build/DerivedData test
```

- 测试是 **App 托管的 `LingoTripTests` bundle**（`bundle.unit-test`，host=LingoTrip），源码在 `Packages/LingoKit/Tests/` 下按被测模块分子目录。**为什么托管**：钥匙串 / SwiftData 等测试在无宿主的 SwiftPM runner 下会报 `errSecMissingEntitlement(-34018)`。
- Mock LLM 在 `Tests/TestSupport/MockLLMProvider.swift`，所有依赖 LLM 的服务都用它做确定性测试。
- **UI 验证**：模拟器 `xcrun simctl` 安装 / 启动 / 截图。`SIMCTL_CHILD_UI_TEST_TAB=home|map|messages|me` 可直接启动到指定 Tab；首页可附加 `SIMCTL_CHILD_UI_TEST_REGION=london|melbourne|newyork` 验证三城背景；`SIMCTL_CHILD_ONBOARDING_AUTOPLAY=1|full` 验证首启；`SIMCTL_CHILD_DEBUG_INJECT_QUIZ=1` 在聊天中注入 quiz 与口语点评卡。

---

## 9. 已知问题与注意事项（踩坑记录）

- **不要在 `Packages/LingoKit` 跑 `swift build`**：残留 `.build/` / `.swiftpm/` 会让 Xcode 报「Missing package product」。清理方式：删掉这两个目录 + `xcodegen generate` + Xcode 里 Reset Package Caches。二者已 gitignore。
- **SourceKit 的「No such module」多为过期索引噪声**：以 `Scripts/build.sh` / `test.sh` 的实际编译结果为准，不要追这类诊断。
- **新增源文件必须重新 `xcodegen generate`**（脚本已每次自动执行），否则新文件不进工程。
- **模拟器顶部导航栏按钮**用合成点击（CGEvent）常打不中，UI 自动化尽量点中部 / 底部控件，或用 DEBUG 注入。
- **Swift 6 并发**：新增跨 actor 数据一律走 `Sendable` DTO；`@Model` 实体别跨线程。
- **新模型不接受采样参数**：给 sonnet-5 / opus-4.7+ 等发请求时不要带 temperature（`AnthropicProvider` 已自动处理，新增 provider 注意对齐）。

---

## 10. 后续可做的方向

功能已按计划全量落地，下一步偏「从模拟到真实」与深化：

1. **接真实支付**：把 `LocalPurchaseGateway` 换成 StoreKit 2 实现（`PurchaseGateway` 协议已就位）。
2. **真机跑通 LLM 全链路**：目前 LLM 相关路径用 Mock 单测 + DEBUG 注入验证 UI，尚未在模拟器配真实 Key 端到端跑；配 Key 后回归 quiz / 记忆级联 / 偶遇生成 / 口语点评。
3. **偶遇头像 / 立绘**：现为字母占位，可接内置多样化头像组或 AI 生图。
4. **更多地区与剧情**：`RegionCatalog` / `MainlineCatalog` + `App/Resources/Stories` 加数据即可扩展；每个地区目前 2 章。
5. **记忆与出题调参**：配额、压缩阈值、出题频率都在 `MemoryService.Config` / `QuizService` 里集中，可按真实体验调。
6. **角色头像美术**：三城正式背景与代码兜底均已完成；角色仍使用 `AvatarBadge` 代码占位，可按资产约定逐步替换。
7. **国际化与无障碍**：文案目前中英混排硬编码，后续可上 `String Catalog`。

---

*补充说明请直接改本文件；重大架构决策请同步更新 `docs/plan.md`。*
