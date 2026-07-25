# LingoTrip（工作代号，可随时改名）— AI 角色聊天学英语 iOS App 开发计划

> **文档属性：历史计划。** 本文保留项目启动阶段的假设、里程碑和原始决策，不描述当前工程状态。当前实现与开发约定以 `docs/HANDOFF.md` 为准。

## Context

全新 greenfield 项目，目录 `/Users/tiantian/eng`（当前为空、非 git 仓库）。产品：通过与世界各地有身份/背景/性格设定的 AI 角色用英语聊天来学外语的 iOS 原生 App，聊天中内嵌 ECDICT 词典查词、翻译、教练纠错、TTS 朗读、语音消息、语境出题；外加 AVG 剧情模块、角色偶遇系统、地区/机票系统、首启引导剧情。

**环境**：Xcode 26.1.1（Swift 6.2）、iOS 26.1 模拟器（iPhone 17 等）、Homebrew 已装（xcodegen 需 `brew install`）、本机无 ECDICT 数据（需下载预处理）。

**已与用户确认的决策**：
1. LLM 接入 = **多供应商抽象层**（Anthropic + OpenAI + 自定义 OpenAI 兼容端点可配 baseURL，Key 存 Keychain，支持流式）
2. TTS = **仅 Apple 本地**（AVSpeechSynthesizer，选最高质量 voice、引导下载增强语音；隐藏在 SpeechService 协议后，未来可换云端）
3. 最低 **iOS 18**，SwiftUI，尽量原生组件 + SF Symbols，符合 HIG
4. 商业化（订阅等级/金币）= **本地模拟**（正式数据模型+逻辑，不接真实支付，留 StoreKit 2 接入点 `PurchaseGateway` 协议）

其他定案：语音输入用 Speech framework（SFSpeechRecognizer 英语）；持久化 SwiftData；词典查询用原生 sqlite3（只读、查询极简，不引第三方）；表情从 emoji 起步；v1 只做英语。

---

## 1. 工程化与总体架构

**XcodeGen（`project.yml` 为唯一工程事实来源，`.xcodeproj` 不入 git）+ 单一本地 Swift Package `Packages/LingoKit` 内分多个 library target**。App target 只做组合根/DI/资源。依赖方向严格向下，Feature 之间互不依赖：

```
App（LingoTrip target：DI、RootView、生命周期、Assets/Resources）
 └─ Feature 层：ChatFeature / OnboardingFeature / StoryFeature / RosterFeature
                MapFeature / FavoritesFeature / SettingsFeature / HomeFeature
     └─ Domain 层：DomainKit（PromptBuilder、Memory/Coach/Translation/Quiz/
                   Encounter/Economy Service、KeywordAnnotator）+ StoryEngine
         └─ Service 层：LLMKit / SpeechKit / DictKit / PersistenceKit
             └─ Infra 层：CoreKit（Keychain、Logger、AppError、TokenEstimator、
                          AudioSessionCoordinator）+ DesignSystem（纯 UI 组件）
```

### 目录结构

```
/Users/tiantian/eng/
├── project.yml                  # XcodeGen 配置（含麦克风/语音识别权限文案）
├── .gitignore                   # 忽略 *.xcodeproj、.build、DerivedData
├── Scripts/{build.sh, test.sh}  # xcodegen + xcodebuild 封装
├── tools/ecdict/build_dict.py   # ECDICT CSV → ecdict_lite.sqlite 预处理脚本
├── App/
│   ├── LingoTripApp.swift / AppEnvironment.swift（DI）/ RootView.swift
│   ├── Assets.xcassets          # 3 主角色头像占位、地区背景、票根素材、偶遇头像组
│   └── Resources/
│       ├── ecdict_lite.sqlite   # 预处理词典（提交进仓库）
│       ├── grammar_points.json  # 手工语法点库（首批 30-50 个高频点）
│       ├── regions.json / main_characters.json
│       └── Stories/*.json       # onboarding_chat + 3 主角色主线脚本
└── Packages/LingoKit/
    ├── Package.swift            # 全部模块 target 与依赖图的唯一清单
    ├── Sources/{CoreKit, LLMKit, SpeechKit, DictKit, PersistenceKit,
    │           DomainKit, StoryEngine, DesignSystem, 各 Feature}/
    └── Tests/                   # Swift Testing
```

### UI 结构（遵循「主页为主入口、少 tab」）

TabView 仅 3 个 tab：**主页**（hub：当前地区卡片、开展活动入口、地图/剧情/票根夹入口、主线提示）、**消息**（会话列表 → 聊天页；收藏夹入口）、**设置**。其余页面全部由主页导航进入，不再加 tab。

---

## 2. 数据模型（SwiftData SchemaV1，用 VersionedSchema + MigrationPlan 占位）

枚举以 String rawValue 存储；跨 actor 只传 Sendable DTO；写操作全部收敛到 `@ModelActor` 仓库（ChatStore / RosterStore / EconomyStore…），UI 用 `@Query` 只读。

| 实体 | 关键字段 | 关系 |
|---|---|---|
| UserProfileEntity（单例行） | displayName, currentRegionID, coins, subscriptionTierRaw(free/plus/pro), friendSlotLimit=10, quizGloballyEnabled, unlockedRegionIDs | — |
| CharacterEntity | name, age, genderRaw, nationality, regionID, occupation, hobbies, appearance, personality, avatarAssetName, difficultyLevelRaw, isMainCharacter, isFriend, cardJSON（原始角色卡，供 prompt 复渲染）, metAt | 1—1 Conversation, 1—* Memory |
| ConversationEntity | createdAt, lastMessageAt, turnCount, turnsSinceQuiz, quizOptOut, lastSummarizedMessageIndex, isEncounterSession | ←Character, 1—* Message(cascade) |
| MessageEntity | roleRaw(user/assistant/coach), kindRaw(text/voice/quiz/storyLine), text, audioFileName?, audioDuration?, orderIndex（显式排序）, tokenEstimate, keywordRangesJSON?, coachReviewJSON?, quizJSON?, translationZh?（翻译缓存） | ←Conversation |
| MemoryEntity | tierRaw(short/mid/long), content（单条事实）, importance(1-5), sourceUpToIndex | ←Character |
| FavoriteEntity | sentence, sourceMessageID?, characterName, translationZh?（弱引用，消息删除不影响收藏） | — |
| ItemEntity | typeRaw(ticketUniversal/ticketCountry), countryCode?, sourceRaw, consumedAt? | — |
| TicketStubEntity | fromRegionID, toRegionID, usedAt, serialNumber, artSeed（决定票根配色花纹） | — |
| StoryProgressEntity | storyID, currentNodeID?, flagsJSON, completedAt? | — |
| QuizRecordEntity | question, optionsJSON, correctIndex, chosenIndex? | — |

难度等级枚举按中国学制：小学 1-6 / 初中 1-3 / 高中 1-3 / 本科 / 研究生 / 更高。地区为静态数据（regions.json），不建实体。语音文件存 `Application Support/VoiceMessages/{uuid}.caf`，DB 只存文件名。

---

## 3. 核心功能技术方案

### 3.1 可点词聊天气泡（最高风险项，最先做原型验证）
- **分词** `WordTokenizer`（纯函数可测）：`NLTokenizer(unit: .word)` 取词界，词+尾随标点/空格合并为一个 token（`display: "Hello, "` / `word: "hello"`），emoji/纯标点 `word=nil` 不可点；按 message.id 缓存。
- **排版**：自定义 `Layout` 协议实现 FlowLayout，每 token 一个 `Text` + `contentShape` + `onTapGesture`；关键词加 `.underline(pattern: .dot)`。气泡外观由外层容器提供。
- **浮窗**：被点词 `anchorPreference` 上报 bounds，聊天根视图 `overlayPreferenceValue` 在词上/下方渲染 `DictCardView`（空间不足自动翻转），渐入动画，点遮罩关闭。卡内释义/例句/语法点中的词继续可点，内部 `path: [DictTarget]` 栈式跳转替换内容；发音按钮走 SpeechService。
- **流式期间**该消息先用普通 `Text`，`finished` 后一次性换 TappableText。
- **降级备胎**：`Text(AttributedString)` + `.link(dict://word)` + `OpenURLAction`（浮窗居中弹），超长消息或性能不济时启用。

### 3.2 语音消息（录制/转写状态机）
- 状态机：`idle / denied / recording(start, inCancelZone, level) / transcribing / failed`。
- 交互：按住说话 `DragGesture(minimumDistance: 0)`，上滑 80pt 进取消区（UI 变红），触觉反馈，60s 自动截断——手感对齐微信/QQ。
- 管线：`AVAudioEngine.inputNode` tap 双路 → ① 写 .caf 文件（气泡点击 AVAudioPlayer 回放）② feed `SFSpeechAudioBufferRecognitionRequest`（en_US 实时识别）；tap 算 RMS 供音量动画。
- `AudioSessionCoordinator`（actor）统一管理 AVAudioSession，录音/播放/TTS 三方互斥 + 打断处理。
- 发送后气泡为语音条（时长+波形），发给 LLM 的是转写文本（kind=voice），同样走教练审核；长按菜单含「查看文字」。
- **模拟器兜底**：`#if targetEnvironment(simulator)` 提供文本注入调试入口，保证全流程可在模拟器验证。

### 3.3 ECDICT 词典
- **预处理** `tools/ecdict/build_dict.py`（Python3 标准库）：下载 ECDICT 全量 CSV（github skywind3000/ECDICT releases），过滤保留 `oxford==1 或 collins>=1 或 tag 非空(zk/gk/cet4/6/ky/toefl/ielts/gre) 或 frq/bnc ≤ 40000`，预计 6-9 万主词条、15-35MB；超 50MB 先砍英文 definition 列再收阈值。产出两表：`word`（全小写唯一索引）+ `lemma`（由 exchange 字段反向展开 looked→look）。脚本打印体积报告，产物提交进仓库。
- **查询**：`actor DictDatabase`，sqlite3 只读打开，预编译语句复用。流水线：lowercase → word 精确 → lemma → 规则回退（去 's/s/es/ed/ing/er/est，双写还原补 e）→ 前缀 LIKE（搜索提示用）。
- **未收录词兜底**：浮窗显示「词典未收录」，提供按钮由 fast 档 LLM 生成简释（明确标注 AI 生成、非词典权威）。
- **语法点**：`grammar_points.json` 手工库，`{trigger: "as", points: [{title: "as...as 和…一样", explanation_zh, examples[], related[]}]}`，按 trigger 词索引，查词时并列展示，related 可跳转。

### 3.4 教练 AI 并行审核
- 用户消息落库后**并行**：主链路流式角色回复 + `Task(priority: .utility)` 调 CoachService（fast 档、JSON 结构化输出：`{has_issues, issues:[{quote, type, correction, explanation_zh}]}`），15s 超时静默放弃。
- 结果写 `coachReviewJSON`，UI 上用户气泡角落出现小黄点角标，点击展开纠错卡（含「采纳」把改法填回输入框）；不打断聊天流，改不改随用户。
- 角色自身的「角色内轻纠错」由 system prompt 固定指令实现（一句话自然带过，不说教）。
- （进阶 2.8）`CoachService.reviewSpeech`：转写文本+时长/停顿粗指标 → 口语流利度建议。

### 3.5 分级记忆
- 三层 MemoryEntity：short（近期事件条目）→ mid（阶段合并）→ long（用户稳定事实）。
- 触发：角色回复完成后检查，`未压缩消息 ≥ 24` 或 `估算 token > 预算×0.7` → fast 档压缩最旧 16 条为 short；short 超配额合并进 mid；mid 溢出提炼 long（用户事实优先、去重）。成功才推进 `lastSummarizedMessageIndex`，失败下次重试（幂等）。
- 注入：PromptBuilder 在 system 尾部拼「[你对 TA 的长期了解] / [最近你们之间发生的事]」，messages 只带最近 rawWindow 条原文。
- 订阅配额（EconomyService）：Free 12/8/5，Plus 24/20/15，Pro 40/40/40（raw/short+mid/long），调试面板可切换并可视化记忆。

### 3.6 剧情引擎（AVG）
- JSON DSL：节点类型 `line（speaker/text/bg/sprite，缺省沿用上一节点）/ choice / branch(flag) / reward(coins/ticket) / end(unlocks)`；加载时静态校验（next 可达、无悬空引用）。
- `StoryPlayer`（@Observable，无 UI 依赖）：`advance() / choose(index) / skipToNextChoice() / isAuto`；reward/unlock 经 delegate 交给 EconomyService/RosterStore；每步写 StoryProgressEntity 可断点续播。
- AVG UI：竖屏 ZStack——背景图+立绘 → 底部对话框（名牌+打字机台词，点击先跳打字再推进）→ 顶部快进/自动/跳过/设置 → 选项中上部垂直排列。台词接 TappableText（剧情里也能查词）。
- **首启剧情复用同一引擎、换渲染皮肤**：在聊天窗口以气泡逐条点击推进（中国朋友通知中奖 → 介绍纽约/墨尔本/伦敦三主角色）→ 三主角色资料浏览页 → 选定一位 → 写 currentRegionID、建主线会话 → 3~5 轮引导对话（主角色 system prompt 附加引导任务清单）→ 发放机票。

### 3.7 角色系统
- 角色卡（CharacterCard DTO + cardJSON）渲染进 system prompt：角色扮演严格性、难度等级语言约束（按学制）、口语化风格指令（随意、句尾可不加标点、偶尔笔误、避免 AI 腔）+ few-shot 示例句；prompt 全部集中在 PromptBuilder 便于迭代，snapshot 测试锁定。
- 3 主角色（伦敦/墨尔本/纽约）手工精心设计（main_characters.json + 内置头像素材），默认进好友列表、不占好友位。
- **偶遇**：主页「开展活动」（逛街/咖啡馆/公园，文案差异）→ EncounterService：P(偶遇)=0.35（可调）→ 60/30/10 掷来源（当地人/本国其他地区/外国人）→ balanced 档 LLM 结构化生成角色卡（带地区约束、用户等级、已有姓名去重、多样性要求），Decodable+字段校验，失败重试 1 次再回退本地模板卡 → 偶遇卡 UI + 开场白。
- **好友位**：默认 10；偶遇界面提供「加好友」（校验空位）；**未加好友只能在当次偶遇中聊**，离开后会话归档只读（对齐规格「只能在遇到的时候聊」）。偶遇头像从内置多样化头像组按角色特征挑选（进阶再接 AI 生图）。

### 3.8 关键词划线 & 语境出题
- 关键词：本地词频方案（确定性/离线/零成本）——KeywordAnnotator 对角色回复逐词查 frq/bnc/tag，超过用户等级阈值（小学 3000 / 初中 6000 / 高中 10000 / 本科 15000 / 研究生 25000）且非停用词 → 划线，缓存 keywordRangesJSON。LLM 标注留作后期增强。
- 出题：`turnsSinceQuiz` 达 N（6±2 随机）且双开关都开 → 下次角色回复请求 system 尾部追加指令，回复末尾输出 `<quiz>{question, options[4], answer, explanation_zh}</quiz>`；流式结束后截取解析（失败当普通文本静默放弃）→ 渲染选项气泡 → 作答本地判定+模板反馈+金币奖励+QuizRecordEntity。气泡角落「不再弹题」勾选写 quizOptOut，设置页有总开关。

### 3.9 地区/机票/票根
- 地图页展示 3 地区（解锁态/未解锁）；机票（通用/指定国家）只用于首次解锁未到访地区，已解锁地区可直接往返。机票来源：主线奖励 1 张 + 金币购买。
- 每次旅行都生成票根（serialNumber + artSeed 决定配色花纹的精美票根卡片）→ 票根夹页面翻阅。

---

## 4. LLM 抽象层（LLMKit）

- 核心类型全 Sendable：`LLMTier(fast/balanced/deep)`、`LLMMessage`、`LLMRequest(tier/system/messages/maxTokens/temperature?/responseFormat: text|json(schema))`、`LLMStreamEvent(textDelta/finished)`。
- `protocol LLMProvider { complete / stream(→AsyncThrowingStream) / modelID(for:) }`；`LLMRouter` 按设置派发 + 统一重试（429/5xx 指数退避×2）。
- 三 Provider：**Anthropic**（`/v1/messages`，`x-api-key` + `anthropic-version: 2023-06-01`，顶层 system，SSE 事件 message_start/content_block_delta(text_delta)/message_delta/message_stop，结构化输出用 `output_config.format.json_schema`）；**OpenAI**（`/v1/chat/completions`，Bearer，`response_format: json_schema`，`data: [DONE]` 结束）；**OpenAICompatible**（复用 OpenAI 实现 + 可配 baseURL，json_schema 400 时降级 prompt 内嵌 schema）。
- 通用 `SSEParser`（URLSession.bytes + lines）+ `JSONExtractor` 兜底链（直接解析 → 剥围栏 → 截取 {} → fast 档重问修复 → 抛错由调用方降级）。
- Key 存 Keychain（service 区分 provider），UserDefaults 只存非敏感配置；设置页有「测试连接」。
- 默认模型（设置页可改）：fast=`claude-haiku-4-5`，balanced=`claude-sonnet-5`，deep=`claude-opus-4-8`（deep 档自动丢弃 temperature 等采样参数）；OpenAI 侧默认占位 `gpt-4o-mini`/`gpt-4o`。
- 任务矩阵：角色扮演=balanced/流式/temp 0.9/max 512；翻译=balanced/temp 0.3（结果缓存 translationZh）；教练纠错&记忆压缩=fast/JSON/temp 0.2；角色卡生成=balanced/JSON/temp 1.0；未收录词简释=fast。

---

## 5. 里程碑（每个单元 = 构建通过 + 一次 git commit）

### M0 脚手架
| # | 单元 | 内容 |
|---|---|---|
| 0.1 | 工程初始化 | git init、.gitignore、brew install xcodegen、project.yml、空 App + RootView 三 tab 占位、Scripts/build.sh；模拟器可启动 |
| 0.2 | Package 骨架 | LingoKit 全部 target 空实现 + CoreKit（Logger/KeychainStore/AppError）、App 依赖接线 |
| 0.3 | 测试基建 | 测试 bundle（Swift Testing）、Scripts/test.sh、KeychainStore 冒烟测试 |

### M1 MVP（能和 1 个主角色像模像样地学英语聊天）
| # | 单元 | 依赖 | 内容 |
|---|---|---|---|
| 1.1 | LLMKit + 设置页 | 0.2 | 协议/SSEParser/三 Provider/Router；设置页供应商+Key+测试连接 |
| 1.2 | 词典管线 | 0.2 | build_dict.py 产出 ecdict_lite.sqlite；DictKit + grammar_points.json 首批；查询单测 |
| 1.3 | Schema + 仓库 | 0.2 | SchemaV1 全实体、ModelContainerFactory、@ModelActor 仓库、3 主角色导入 |
| 1.4 | 聊天核心 | 1.1,1.3 | ChatFeature 消息列表/输入栏/流式回复/PromptBuilder v1/会话持久化 |
| 1.5 | 可点词渲染 | 1.2,1.4 | WordTokenizer/FlowLayout/TappableText/DictCardView 浮窗跳转/关键词划线（先做性能原型） |
| 1.6 | 消息操作+TTS+收藏 | 1.4 | 长按菜单四功能、AppleTTSService（最高质量 voice+增强语音引导）、翻译服务、收藏夹页（句内可点词） |
| 1.7 | 教练流水线 | 1.4 | CoachService+角标+展开纠错卡 |
| 1.8 | 语音消息 | 1.4 | 录制状态机、按住说话、语音气泡、模拟器注入兜底 |
| 1.9 | 记忆 v1 | 1.4 | short 层压缩+注入+触发（单测） |
| 1.10 | 首启引导 | 1.4 | StoryScript/StoryPlayer + 聊天皮肤 onboarding、选主角色、引导主线、发机票 |

1.1/1.2/1.3 三线并行，1.4 为汇聚点。

### M2 完整版
| # | 单元 | 依赖 | 内容 |
|---|---|---|---|
| 2.1 | AVG 剧情模块 | 1.10 | 竖屏 AVG UI 全套 + 3 主角色主线脚本各 1 章 |
| 2.2 | 经济系统 | 1.3 | EconomyService：金币/订阅（本地模拟+PurchaseGateway 占位）/调试面板 |
| 2.3 | 地区/机票/票根 | 2.2 | 地图页、机票使用、票根生成+票根夹 |
| 2.4 | 偶遇系统 | 2.2,2.3 | EncounterService、偶遇卡、好友位、好友列表/资料页、未加好友仅当场可聊 |
| 2.5 | 语境出题 | 1.4 | 内联 quiz、选项气泡、奖励、双开关 |
| 2.6 | 记忆完整版 | 1.9,2.2 | mid/long 层、订阅配额、记忆调试面板 |
| 2.7 | 打磨 | 全部 | 空态/错误态/触觉/深色模式/App 图标/剧情补章 |
| 2.8 可选 | 口语点评 | 1.7,1.8 | CoachService.reviewSpeech |

---

## 6. 构建与验证

```bash
xcodegen generate    # project.yml 变更后
xcodebuild -project LingoTrip.xcodeproj -scheme LingoTrip \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.1' -quiet build   # 每单元提交前必过
xcodebuild ... -quiet test
xcrun simctl boot "iPhone 17"; xcrun simctl install booted <path>/LingoTrip.app
xcrun simctl launch booted com.lingotrip.app   # 关键节点截图人工验收
```

`Scripts/build.sh` 启动时用 `simctl list devices available` 自动挑选可用 iPhone 机型，避免设备名漂移。

**单测重点**（全部 Service 依赖 LLMProvider 协议 → MockLLMProvider 注入，零网络）：DictKit（fixture 迷你库：精确/词形还原/回退）、WordTokenizer（标点粘附/缩写/emoji）、SSEParser+Provider 解析（SSE 文本 fixture）、JSONExtractor、StoryPlayer（分支/flag/续播/脚本校验器）、MemoryService（触发/配额）、EconomyService（金币/好友位/机票）、PromptBuilder（按等级 snapshot）。不测 SwiftUI 视图与真机音频（人工冒烟清单）。

---

## 7. 主要风险与规避

| 风险 | 规避 |
|---|---|
| SwiftUI 文本无法命中单词（核心交互） | FlowLayout 逐词方案 + AttributedString/link 降级备胎；1.5 最先做原型验证性能 |
| ECDICT 体积失控 | 分级过滤目标 <35MB，超限砍 definition 列/收紧阈值，脚本打印体积报告 |
| SFSpeechRecognizer 模拟器不可用 | 模拟器文本注入兜底；权限预请求 + denied 态 UI |
| Swift 6 严格并发 + SwiftData | 写操作全收敛 @ModelActor，跨界只传 Sendable DTO，UI @MainActor+@Query |
| 兼容端点不支持 json_schema/SSE 差异 | 降级链 + JSONExtractor + 本地模板兜底；SSE 未知事件宽容忽略 |
| 角色回复 AI 腔 | PromptBuilder 集中管理 + 风格指令 + few-shot + snapshot 测试 + 持续调优 |
| 录音/TTS/播放 AVAudioSession 冲突 | AudioSessionCoordinator 单点管理 + 打断处理 |
| 流式中途断网 | 已收 delta 落库标 interrupted，气泡提供重试 |
