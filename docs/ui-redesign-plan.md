# LingoTrip UI 全面重构计划（视觉风格 + 结构重设计）

> 状态：**已实施并通过构建、测试与浅/深模式截图回归**（2026-07-25）。本文记录视觉与信息架构；当前工程事实以 `docs/HANDOFF.md` 为准。

## Context（背景）

LingoTrip 是 SwiftUI 原生 iOS 语言学习 app。重构前的 UI 以原生控件平铺为主，缺少统一品牌视觉和成熟的信息架构。本轮做两层重构：

**A. 视觉层**：保留原生组件行为的前提下定制外观，对标多邻国的简单、灵动风格与小动画。已拍板：**天空蓝青主色**、**SF Rounded 圆体**、**原生 TabView 行为 + 品牌化样式**。

**B. 结构层**：页面布局、信息架构按成熟 App 标准大规模重设计，功能不受影响。已拍板：
- **四 tab**：首页（聚合 hub）/ 地图 / 消息 / 我的
- **首页 = 游戏式聚合 hub**：不做硬 hero 大卡，头部轻量透出城市信息；背景为当前城市**半写真半卡通动态背景**（视差/缓动）；模块含新消息/最近会话（核心）、功能入口（主线剧情、活动/偶遇→二级页）
- **地图 = MapKit + overlay**：平面洲级宽视角选地点、城市 pin；只保留原生平移/缩放，前往时**蓝底飞机动画全屏转场**；票根入口归地图 tab
- **消息 = QQ 式成熟消息列表**：会话列表为主体，好友/角色资料收二级页（Roster 本轮做基础版）
- **我的**：收藏、订阅/账户、设置（降级为二级页）
- **开局引导重设计**：剧情聊天流里主角色信息做成消息卡片；选角改左右滑动实体感角色卡

约束：不引入第三方库（MapKit 是 Apple 框架，允许；无 Lottie）；功能不受影响；不动 ViewModel 业务逻辑（允许加纯查询/组装层）；国际化暂不管。**每个任务独立 commit（构建与全量测试通过为门槛）**。

## 工程事实（已调研核实）

- iOS 18 / Swift 6 严格并发 / XcodeGen（`Scripts/build.sh`、`Scripts/test.sh` 自动 `xcodegen generate`）。单一本地包 Packages/LingoKit 严格分层，Feature 间零依赖（跨 Feature 跳转由 App 组合根闭包/`AnyView` 注入）。
- **`DesignSystem` 模块已在 Infra 层**，8 个 Feature + DictKit 已全部依赖——就地扩建，零依赖图改动。现有仅 256 行（MessageBubble/TappableText/FlowLayout/Haptics）。
- `AccentColor.colorset` 是空的（系统蓝）；深色模式纯靠语义色；两处硬编码 RGB 不适配深色（AVGStoryView `BackgroundPalette`、TicketStubsView 票根 palette）；0 自定义 ButtonStyle；圆角 10-18 混用；头像徽章/chip/批注卡三类模式重复未抽象。
- `Region`（DomainKit/World/RegionCatalog.swift）**无经纬度**——需给 struct + regions.json 加坐标；`ChatStore.conversationSummaries()` 已存在（首页最近会话直接复用）；RosterStore 已就位（好友标记、cardJSON）。
- `StoryPlayer.Line` 已透出可选 `sprite` 字段——引导消息卡片零 StoryEngine 改动。
- DEBUG 验证钩子已核实存在：`ONBOARDING_AUTOPLAY=1|full`（OnboardingFlowView:70）、聊天工具栏「注入小测」（ChatView:41）、「模拟语音注入」（ChatView:481）、`DEBUG_INJECT_QUIZ=1`。

---

## 一、设计语言（token）

### 色板（全部 dynamic 深浅双值，落 `DSColor.swift`，代码定义为唯一事实源）

| Token | 浅色 | 深色 | 用途 |
|---|---|---|---|
| `dsSky` | `#1BA8F0` | `#4CC2FF` | 主品牌色：CTA、选中态、outgoing 气泡、tab 选中 |
| `dsSkyDeep` | `#1486C6` | `#2B87BD` | 3D 按钮底边 |
| `dsCyan` | `#00BFC7` | `#33D6DD` | 青色点缀、航线元素 |
| `dsSunset` | `#FF9600` | `#FFB340` | 金币、票根入口、庆祝粒子 |
| `dsSuccess` / `dsWarning` / `dsDanger` | `#2FBF63`/`#F5A700`/`#FF4B4B` | `#4ADE80`/`#FFC93D`/`#FF6B6B` | 结果/警示/危险 |
| `dsCoach` / `dsSpeech` / `dsQuiz` | `#D18E00`/`#0E9BAF`/`#7A5AF8` | `#FFC93D`/`#35CADF`/`#A78BFA` | 三种批注卡 tint（卡底 = tint.opacity 浅 0.13/深 0.18） |
| `dsBubbleIncoming` | `#EFF4F9` | `#262B33` | 气泡/输入框底（替 systemGray5/6） |
| `dsBackground` | `#F3F8FC` | `#14181D` | 微天蓝调页面底；Form/List 保持系统 grouped |
| `dsSurface` | `#FFFFFF` | `#1E242B` | 卡片面 |

配套：`Color(light:dark:)` helper（UIColor dynamicProvider）；补填 `AccentColor.colorset` 同组双值（系统组件自动同色，注释注明手工同步）；根视图 `.tint(.dsSky)` 兜底。

### 圆角 / 间距 / 阴影 / 字体 / 动画

- `DSRadius`：inline 12 · card 16 · bubble 18 · hero 24，全 `.continuous`。`DSSpacing`：4/8/12/16/20/24。
- 阴影：浅色卡 `black.opacity(0.05), r8, y2` + 可选 `#E4EDF4` 描边；深色改 `white.opacity(0.06)` 描边（内置于 `.dsCard()`）。
- 字体：全局 `.fontDesign(.rounded)` 挂 WindowGroup 根（中文回退苹方）；导航栏标题需 `DSTypography.configureNavigationBarAppearance()`（`@MainActor`，UIKit appearance）在 App init 调；语义字号层级不变（Dynamic Type 保留）。
- `DSAnimation`：`press` easeOut 0.08 · `snappy` 0.25 · `bouncy` spring(0.35, 0.62) · `pop` spring(0.28, 0.5) · `gentle` easeOut 0.2。
- `DSScenePalette`：城市主题色（首页背景/选角卡）、AVG 7 场景渐变、票根 6 套渐变，全部深浅双值（深色降亮 ~20%、降饱和 ~10%）。

## 二、DesignSystem 扩建（文件结构与 API 要点）

```
DesignSystem/
├── Tokens/     DSColor · DSLayout(Radius/Spacing) · DSAnimation · DSTypography · DSScenePalette
├── Styles/     DuoButtonStyle · PressableCardStyle · DSCard(.dsCard()) · DSMaterial(.dsMaterial())
├── Components/ AvatarBadge · DSChip · CalloutCard · CelebrationBurst · TabBarVisibility
└── 现有：MessageBubbleView（内部 token 化，签名不变）· TappableText · FlowLayout · Haptics
```

- **`DuoButtonStyle`**（多邻国 3D 按钮）：variant `primary`/`success`/`tinted(Color)`/`outline`，`fullWidth`/`compact`；双层 RoundedRectangle，底边 4pt，按下面层 offset(y:4) 吃掉底边 + `Haptics.impact(.light)`；便捷入口 `.duoPrimary`/`.duo(...)`。
- **`PressableCardStyle`**：scale 0.97 + opacity；**`.dsCard(padding:radius:)`**：dsSurface 底 + 浅色投影/深色描边。
- **`.dsMaterial(_:in:)`**：系统材质背景；开启 Reduce Transparency 时自动降级为不透明 `dsSurface`。
- **`AvatarBadge(name:tint:size:)`**：36/46/56/88pt；tint nil 时按 name 哈希 6 色盘稳定取色；Circle tint.opacity(0.15) + 首字母 rounded bold。
- **`DSChip(_:tint:prominent:)`**：Capsule caption2，tint.opacity(0.12) 底；prominent 实底白字。
- **`CalloutCard(kind:maxWidth:trailing:content:)`**：kind 预设 `.coach`/`.speech`/`.quiz`（tint+icon+title），统一骨架（标题行+trailing 槽+content）。
- **原生 `TabView` + `.tabItem`**：系统负责切换、重选、导航状态、安全区、键盘避让、badge 与辅助功能；品牌层只设置 `Color.dsSky` tint，不覆盖点击层。
- **`TabBarVisibility`**：`.dsTabBarHidden(_:)` 直接映射系统 `.toolbar(visibility, for: .tabBar)`，由导航层级自动恢复。
- **`.celebration(_:tint:trigger:)`**：12–14 粒星形/圆点（dsSunset/dsSky/dsSuccess），keyframeAnimator 0.8s 外抛+旋转+淡出；ReduceMotion 降级 opacity 闪现。

每组件自带 `#Preview`（浅/深 + `.dynamicTypeSize(.accessibility1)`）。

## 三、信息架构与 RootView 目标结构

```
RootView
├─ @State selectedTab: AppTab { home, map, messages, me }
├─ TabView(selection:)（每 tab 通过 .tabItem 注册原生栏）
│   ├─ home:     NavigationStack { HomeView }
│   │     navigationDestination: HomeDestination(.mainline/.activities) + MainlineChapter→AVGStoryView（保留）
│   ├─ map:      NavigationStack { MapView }（票根 MapFeature 内部 push）
│   ├─ messages: NavigationStack { ConversationListView }（toolbar 好友入口→AnyView(RosterView)）
│   └─ me:       NavigationStack { MyPageView(favoritesBuilder:) }（→SettingsView 二级页）
└─ fullScreenCover: OnboardingFlowView（不变）
```

跨 Feature 接线（全部组合根注入，Feature 零依赖不变）：`chatBuilder(CharacterDTO)->AnyView`（现 encounterChatBuilder 泛化改名，注入 Home/Roster）、`onOpenMessages`（首页「查看全部」切 tab）、`favoritesBuilder`（我的→收藏）；`HomeDestination` 删 `.map/.ticketStubs` 增 `.mainline/.activities`；声明 `.dsTabBarHidden(true)` 的页面：ChatView、AVGStoryView、TicketStubsView、飞行转场期间。

## 四、逐页面结构设计

### 首页（HomeView 重写，游戏式聚合 hub）
ZStack 两层：**背景层 `CityBackdropView`**（全屏 ignoresSafeArea）= 天空渐变（DSScenePalette.city 深浅双值）+ 13 城正式生成式素材（`city_backdrop_<regionID>`）+ **代码自绘兜底 `CitySilhouetteView`**（landmarks 关键词→钟塔/桥/树冠/hash 播种天际线，2-3 层剪影叠景深 + TimelineView 云朵漂移）+ scrim 渐变保可读；滚动 `onScrollGeometryChange` 驱动受限视差，ReduceMotion 全静止，深色模式自动压低亮度与饱和度。内容在城市 HUD 与最近会话间保留约 196pt 景观窗口（紧凑高度 / 辅助功能字号自动缩短），让城市地标完整露出并贴近预览稿比例。
**内容层**：`HomeStatusBar`（取消整块材质卡，国旗徽章 + 当前城市/国家直接叠在场景上；右侧两个紧凑 HUD 资源槽展示真实 `difficultyLevel` 与金币，辅助功能字号自动改为纵向布局）→ `RecentChatsCard`（.dsCard：最多 3 条最近会话，`conversationSummaries()` join `friends()`，AvatarBadge+摘要+相对时间+未读红点；行点击 chatBuilder 进聊天；「查看全部 ›」onOpenMessages；空态引导语）→ **探索入口区**（两张 88pt 横幅大卡 PressableCardStyle：左侧单一品牌实色承载文字，以短透明度渐变干净过渡到右侧 `home_mainline_<regionID>` / `home_activity_<regionID>` 生成式场景美术；主线剧情卡带进度 x/y 章 → `.mainline`；活动卡 → `.activities`）。删除旧 regionCard/entryGrid/内嵌 EncounterSection/章节列表。

### 主线剧情二级页 `MainlineListView`（新）
展示由初始角色决定的五座必经城市与总进度；章节卡三态：已完成（绿勾+淡化）、当前目标（DSScenePalette 渐变高亮）、后续站（锁定）。只有已完成/当前目标且玩家身处对应城市时才可进入章节；其余状态明确提示前往目标城市或完成上一站。push `MainlineChapter` 命中现有 destination。

### 活动二级页 `ActivitiesView`（新，EncounterSection 逻辑整体迁入）
城市 chip + 活动大卡纵列（region.activities 每项一卡：emoji+标题+副文案+「出发」）；点击骰运中 loading 态；`runActivity` 业务逻辑原样搬（EncounterService→落库→EncounterCardSheet）；未遇到内联 toast；EncounterCardSheet 逻辑不动仅换肤。

### 地图页（MapView 重写为 MapKit）
数据前置：`Region` 包含 `latitude/longitude` 与 `mainline/side` 角色；`regions.json` 配置 5 座主线城市、8 座支线城市。坐标转换放 MapFeature，DomainKit 保持纯 Foundation。
`Map(position:interactionModes:)` 只开放 `.pan/.zoom`，配合 `.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false)`；初始镜头同时容纳当前城市与剧情引导目的地，heading/pitch 均为 0。隐藏正式地图应用才需要的指南针、比例尺、用户定位、俯仰和旋转；**CityPinView 三态**为紧凑国旗标记（当前/已解锁/未解锁），选中后在标记下方原位显示“前往 / 使用机票 / 购买机票 / 已在这里”。底部 `JourneyGuideView` 不展示当前选中城市，而按 `MainlineCatalog` 显示下一座必经城市、双目的地、多个横滑目的地、继续主线或完成回退态。机票只用于首次解锁未到访城市；首次抵达为该目的地签发唯一纪念票根，已解锁城市直接往返且不消耗机票、不重复生成票根。票根夹保留在顶部。
**`FlightTransitionOverlay`**（新）：TravelSheet 成功分支不再 alert，改 fullScreenCover 动画序列：起飞（蓝底渐变+出发/抵达城市）→ 航线（白虚线弧线+✈️ 沿弧飞行+云层反向流动）→ 降落。首次解锁走隆重的“城市收藏 +1”分支，展示带目的地场景、唯一编号与日期的完整纪念票根并触发庆祝粒子；自由往返走克制的“欢迎回来”分支并明确不产生新票根。ReduceMotion 直接交叉淡入结果态；失败分支维持 alert。

### 消息页（ConversationListView 重做，QQ 式）
大标题「消息」+ toolbar 好友入口（person.2 → RosterView）；行 = AvatarBadge 48pt + 未读红点徽章 + 名字/智能时间（今天 HH:mm、昨天、星期、M/d）+ 摘要（语音→「[语音]」、quiz→「[小测验]」）；置顶行浅主色底衬排前；滑动操作 = 置顶/标记已读（**不做删除**——非现有能力）；`.searchable` 按名字过滤。
**未读实现（不动 Schema）**：新 `ConversationListState.swift` — `LastReadTracker`（UserDefaults 存 conversationID→lastReadAt，未读 = lastMessageAt 更新且末条为 assistant；进 ChatView 标记已读）+ 置顶 ID 集合。原生消息 Tab 通过 `.badge(unreadCount)` 展示角标。

### 好友二级页 + 角色资料卡（RosterFeature 基础版）
`RosterView`：好友位使用条（occupiedFriendSlots/friendSlotLimit）+ 分区（伙伴=isMainCharacter / 旅途遇到的朋友）+ 行（AvatarBadge+名字+国籍+职业）。
`CharacterProfileView`：hero（88pt AvatarBadge+名字+年龄/国籍/职业 chips）+ 信息区（cardJSON 解码：性格/爱好 DSChip flow/外貌/说话风格/背景/相识于）+ `DuoButton`「发消息」→ chatBuilder。**不复用 HomeFeature 私有偶遇卡视图**（Feature 零依赖），用同套 DS 组件达成同款骨架。
接线：`Package.swift` 给 RosterFeature 加 `PersistenceKit` 依赖；RosterDependencies + chatBuilder 由 RootView 组装。

### 我的页（MyPageView 新增，放 SettingsFeature 不新开模块）
头部资料卡（AvatarBadge+displayName+订阅档 chip+金币大数字）→ 订阅卡（渐变卡+权益一句话+「更换」展开现有档位 Picker 逻辑，从 SettingsView accountSection 搬入含「本地模拟」footer）→ 入口列表（收藏夹→favoritesBuilder；设置→push 瘦身版 SettingsView（AI 服务/模型/测试连接/学习开关）；DEBUG：+500 金币、记忆调试面板）。

### 开局引导重设计（OnboardingFeature）
**消息卡片**：给 `onboarding_chat.json` 三条介绍行加 `"sprite": "card:london|melbourne|newyork"`（StoryEngine 零改动）；ChatStoryView 遇 `card:` 前缀且与上一行不同 → 气泡下追加 **`CharacterIntroCard`**（AvatarBadge+名字+「🇬🇧 伦敦 · 24 岁 · 职业」+hobbies chips+personality，名片样式描边微阴影；数据源 = 已加载的 SeedData 主角色按 regionID 匹配）；autoplay 路径保持可用。
**实体感选角卡**：`CharacterSelectView` 拆出重写——横向 `ScrollView` + `.scrollTargetLayout()` + `.scrollTargetBehavior(.viewAligned)` + 卡宽 ~78% `containerRelativeFrame`；`.scrollTransition` 非居中卡 scale 0.92 + y 轴 `rotation3DEffect` + 阴影减淡（卡牌翻检手感）；卡面 = DSScenePalette 城市渐变 + 国旗邮票角标 + AvatarBadge + 资料 + 厚描边双层阴影；snap 时 `sensoryFeedback(.impact)`；底部 DuoButton 文案随居中卡变（「去伦敦找 Oliver」），确认 → 居中卡 spring 放大 + CelebrationBurst → onSelect（链路不变）；`ONBOARDING_AUTOPLAY=full` 兼容。

### 聊天页（结构微调，消息流不动）
`.toolbar principal` 自定义导航头（AvatarBadge 32pt+名字+状态小字「⌖ 伦敦 · 难度」/「偶遇中」，数据在 viewModel.character）；`.dsTabBarHidden(true)`；三批注卡收编 CalloutCard（★星级走 trailing 槽）；quiz 答对 `.celebration` + `.sensoryFeedback(.success)` + 金币 `contentTransition(.numericText())`，答错 keyframe 横向 shake + `.error`；coach 小黄点 `symbolEffect(.pulse)`；输入栏材质化+发送钮主色；VoiceInputBar 两处直调 generator（63/69 行）收编进 `Haptics`，录音态 dsSky/取消区 dsDanger、按住 label phaseAnimator 呼吸；TypingIndicator 手写循环改 phaseAnimator。

### 长尾换肤
DictCardView（chip→DSChip、例句底→dsBubbleIncoming、AI 解释钮→`.duo(.tinted)`、浮窗入场 scale+bouncy）；FavoritesView（List 原生保持、星标 dsSunset、空态）；AVGStoryView（BackgroundPalette→DSScenePalette 深浅双值、名牌 dsSky、选项 `.duo(.outline)`、立绘 phaseAnimator 浮动）；TicketStubsView（palette→DSScenePalette.ticket、深色投影改描边、入场 stagger）；SettingsView/MemoryDebugView 保持原生 Form 吃全局 rounded+accent。

---

## 五、任务拆分表（每任务 = 构建 + 全量测试通过 + 一次 commit）

> 每项验收基线：`Scripts/build.sh` + `Scripts/test.sh` + 指定截图（`xcrun simctl` 浅/深双模式）。表中只写增量验收。未列前置即可并行。

| # | 任务（commit 风格） | 涉及文件 | 增量验收 | 前置 |
|---|---|---|---|---|
| 1 | `feat(design): token 地基 + 全局 rounded/tint/AccentColor` | DesignSystem/Tokens/ 5 文件、LingoTripApp.swift、AccentColor.colorset | 任意页截图：主色天空蓝、圆体生效、深浅双模式 | — |
| 2 | `feat(design): DuoButtonStyle / PressableCardStyle / .dsCard()` | Styles/ 3 文件 | Preview：按压位移/缩放动效 | 1 |
| 3 | `feat(design): AvatarBadge / DSChip / CalloutCard / CelebrationBurst` | Components/ 4 文件 | Preview：哈希配色稳定、三卡骨架、粒子 | 1 |
| 4 | `refactor(app): 四 tab 骨架 + 原生 Tab 行为 + 导航迁移` | 原生 TabView/TabBarVisibility、RootView 重写、AVGStoryView/ChatView 挂 dsTabBarHidden、MapView 票根入口暂挂 | 4 tab 截图（me 暂显 SettingsView）；进聊天/AVG 藏栏返回恢复；系统切换、badge 与 a11y 正常 | 1,3 |
| 5 | `feat(domain): Region 加经纬度 + regions.json 三城坐标` | RegionCatalog.swift、regions.json | 测试全绿（默认值保 fixture） | — |
| 6 | `feat(home): 城市动态背景（DSScenePalette 城市色+剪影兜底+视差+scrim）` | DSScenePalette、CityBackdropView.swift、HomeView（仅挂背景） | 3 城截图、深浅、视差录屏 | 1 |
| 7 | `feat(home): 主线剧情二级页 MainlineListView` | MainlineListView.swift、RootView(.mainline) | 0 完成/部分完成两态；进 AVG 完成回流 | 2,4 |
| 8 | `feat(home): 活动二级页 ActivitiesView（偶遇整体迁入）` | ActivitiesView.swift（吸收 EncounterSection）、RootView(.activities) | 活动卡/骰运中态；偶遇 sheet→聊聊/加好友链路 | 2,4 |
| 9 | `refactor(home): 首页聚合 hub 重排（信息条+最近会话+探索入口，删旧布局）` | HomeView 重写、RecentChatsCard.swift、RootView（chatBuilder/onOpenMessages，删 .map/.ticketStubs） | 新首页两态；会话点击进聊天；查看全部切 tab；两个二级页可达 | 6,7,8 |
| 10 | `feat(map): MapKit 二维目的地选择器（宽视角/pin 三态/城市卡/票根落位）` | MapView 重写、CityPinView.swift、TicketStubsView 入口 | 平面宽视角/原生平移缩放/pin 城市卡三态；TravelSheet 购票出行回归；票根可达 | 4,5 |
| 11 | `feat(map): 蓝底飞机全屏转场 FlightTransitionOverlay` | FlightTransitionOverlay.swift、MapView | 完整转场录屏；镜头落新城市；ReduceMotion 淡入；失败仍 alert | 10 |
| 12 | `refactor(chat): 消息列表 QQ 化（未读/置顶/滑动/智能时间/搜索）` | ConversationListView 重做、ConversationListState.swift、ChatView 进入即已读 | 未读红点、置顶排序、滑动菜单、搜索；返回未读消失 | 3,4 |
| 13 | `feat(roster): 好友列表 + 角色资料卡（基础版）` | RosterView/CharacterProfileView.swift、Package.swift(+PersistenceKit)、RootView 接线 | 分区列表+好友位条；资料卡全字段两态；发消息进聊天 | 3,4 |
| 14 | `refactor(chat): 聊天导航头 + 气泡/输入栏/语音条 token 化 + 触觉收编` | ChatView、MessageBubbleView、VoiceInputBar | principal 导航头；双侧气泡新样式；语音条/查词浮窗回归；直调 generator 清零 | 3,4 |
| 15 | `refactor(chat): 批注卡收编 CalloutCard + quiz 庆祝/shake + sensoryFeedback` | ChatView（三卡） | `DEBUG_INJECT_QUIZ` 截图三卡；答对粒子/答错抖动录屏 | 14 |
| 16 | `feat(settings): 我的 tab（MyPageView）+ SettingsView 降级瘦身` | MyPageView.swift、SettingsView、RootView（favoritesBuilder、删消息 toolbar ⭐） | 我的页；订阅切换生效；收藏可达；设置二级页全功能保留 | 4 |
| 17 | `feat(onboarding): 剧情流角色消息卡片（sprite card 标记 + CharacterIntroCard）` | onboarding_chat.json、OnboardingFlowView、CharacterIntroCard.swift | 重置首启：三张名片卡不重复渲染；StoryScript 测试全绿；autoplay 可跑 | 3 |
| 18 | `feat(onboarding): 实体感左右滑动选角卡` | CharacterSelectView.swift 拆出重写、OnboardingFlowView | 滑动 snap+3D 倾斜录屏；按钮文案随卡变；确认庆祝后 currentRegion 正确；autoplay=full 通 | 3,17 |
| 19 | `refactor(story): AVG/票根配色迁 DSScenePalette + AVG 换肤` | AVGStoryView、TicketStubsView、DSScenePalette | AVG 两场景深浅双模式；票根 6 配色不回退 | 6 |
| 20 | `refactor(dict): 词典浮窗/收藏页换肤` | DictCardView、WordLookupOverlay、FavoritesView | 词典卡新样式+浮窗入场动画；查词链路回归（Chat/AVG/收藏三入口） | 3 |
| 21 | `chore(app): 全局回归打磨（深色全检/空态/泄漏复检/HANDOFF 更新）` | 各处小修、docs/HANDOFF.md、docs/plan.md | 全 tab+二级页截图集（浅/深）；四 tab 互切×push/pop 无栏异常；文档更新 | 全部 |

**排序逻辑**：1-3 视觉地基 → 4 骨架一次性完成导航迁移（后续不再动路由）→ 5 可并行 → 7/8 先建二级页再 9 重排首页（避免旧首页换肤返工）→ 10/11 地图、12-15 消息聊天、16-18、19/20 可并行 → 21 收尾。FavoritesView 旧 ⭐ 入口保留到任务 16 一并移交，避免中间态功能不可达。

## 六、风险与预案

1. **MapKit 宽视角与标注可见性**：三城跨越超过 180° 经度，竖屏无法同时清晰展示全部标注——以当前城市的洲级宽视角作为初始画面，顶部城市 chips 作为全量目的地入口；切换后目标 pin 必须位于可用内容区内。
2. **无网络地图底图空白**：Map 底垫 DSScenePalette 深蓝渐变；城市卡/出行流程不依赖瓦片。
3. **动态背景无素材**：剪影自绘是默认路径而非降级；scrim 恒在；素材命名约定写进 HANDOFF，后续投图零代码。
4. **TabBar preference 跨 tab 泄漏**：`[AppTab: Bool]` 按 tab 记录；任务 4 显式验收「A tab 深层隐藏→切 B tab 必须显示」；任务 21 复检 fullScreenCover 叠加场景。
5. **3→4 tab 导航迁移回归面**：`MainlineChapter` destination 必须留在首页栈否则主线点击静默无响应；偶遇 fullScreenCover 聊天与消息 tab push 聊天两条路径都要回归。
6. **测试面**：Region 字段带默认值保 fixture；onboarding_chat.json 只加已有可选字段 sprite（StoryScriptTests 不受影响）；未读/置顶走 UserDefaults 零 Schema 迁移；现有 DS 组件只加默认参数不改形参。刻意用闭包注入回避 CharacterDTO 补 Hashable。
7. **Swift 6 并发**：token `static let Color`（Sendable）；dynamicProvider 闭包只捕获字面量；appearance 配置 `@MainActor`；转场分相动画注意 Task 取消传播；`onScrollGeometryChange` 回调轻量；禁止新增 `@unchecked Sendable`。
8. **Rounded 中文回退**：中文自动回退苹方无需处理；导航栏标题漏配 appearance 则仍默认体（易查）。

## 七、验证方案

每任务固定流程：
1. `Scripts/build.sh` → `Scripts/test.sh`（全量通过为硬门槛）→ commit。
2. 双模式截图：`xcrun simctl ui <UDID> appearance light|dark` + `simctl io screenshot`；首启 `SIMCTL_CHILD_ONBOARDING_AUTOPLAY=full` 直达主界面（`=1` 停选角页核对任务 17/18）。
3. 聊天卡片：模拟器 ChatView 工具栏「注入小测」+「模拟语音注入」验证三卡/庆祝/shake；口语点评卡样式靠 CalloutCard preview mock。
4. 专项：tab 弹跳/pill/跨 tab 泄漏、飞行转场全程、键盘盖栏、`simctl ui content_size extra-extra-large` 抽查 Home/Chat、Reduce Motion 降级、无网络开地图。
