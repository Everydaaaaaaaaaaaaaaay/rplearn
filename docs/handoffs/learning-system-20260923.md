# 学习系统实装与真机循环验收交接

更新时间：2026-09-23。请先读本文件，再按需要读关联代码。**任务尚未完成，不是上线验收通过。**

## 最新用户指令与暂停点

用户要求将共同篇章学习原型实装到正常聊天中，不允许必须通过角色资料页进入。实装后，在用户真实 iPhone 上模拟真实用户操作，使用真实模型、真实打字节奏，逐轮记录并修复交互、评分标准、量化、样式和异常恢复问题；每轮扩大未覆盖场景。重点是交互与量化标准，不能仅靠单元测试或免登录回放宣称端到端通过。

用户此前要求持续推进，非必要不停止。有限测试不能证明没有任何问题，不要作零缺陷承诺。当前用户为了切换模型要求交接文件，未取消原任务。

**最新消息：用户已经回复“好了，继续”**，表示此前要求的手机网络、解锁和 UI 自动化准备已处理。但该回复后没有执行任何新检查；随即用户要求写交接。因此新对话应该直接重新验证手机并继续，不要重复要求用户准备，也不要沿用此前“仍阻塞”的结论。

## 已授权与工作边界

- 允许真实手机安装、真实模型评估和正常 NPC 聊天测试；后台变更依 AGENTS.md 既有授权完成检查后部署并验证。
- 保留真实账号、聊天、历史成绩、数据库、积分与限额。不能清空、伪造登录、重置限额以制造通过。
- 不评估口语/发音。听力用项目 TTS，无字幕选择题，不能换为 Apple 系统朗读。
- 英语能力证据与参与经验/旅程等级分离；现有阈值是待校准的产品规则，不是 CEFR 认证。
- 先查 git status；逻辑变更通过适当检查后定向提交。未要求推送，不要假定已推送。
- 不调用 swift build；使用 Xcode-hosted Tests。完成 iOS 后 Scripts/preview.sh 安装模拟器预览。
- 不开子代理，除非用户或适用指令明确要求。
- 已使用 apple-design skill；之前已读其 SKILL.md。只在相关设计工作需要时使用，不涉及 Figma。

## 仓库和当前状态

- 仓库 `/Users/tiantian/eng`，分支 main；交接前工作区干净。
- 最新实现提交 `ad4a48d7`：正常聊天学习入口、同意/暂停、反馈、练习、同步、UI 验证。
- `fcec77d1`：账户学习状态后台、独立学习评估路由，已部署。
- `ea1ab123`：被新消息取消的旧流不再发布“空回复”临时报错。
- `df8d5be8`：首气泡送达计算扣除已显示的打字时间，避免重复等待。
- `e746c4f2`：GLM 聊天推理输出预算由512提高到2048（仍受路由2400上限约束），修复仅推理用尽预算导致空回复。

## 实装架构和主要路径

### 聊天与反馈

- `App/LearningChatAccessory.swift`：正常聊天顶部紧凑入口，可展开的滚动卡片（最大210pt）；直接开启/暂停、接受练习、查看反馈、结束练习、暂缓24小时、打开可选详情/听力。
- `App/ConversationLearningSystem.swift`：账户模型、文件存储、回顾队列、挑战上下文、用量预算、反馈收据、云同步。
- `App/ConversationLearningDashboard.swift`：可选详情页，从聊天直接打开；已移除原来联系人资料里的原型入口。
- `App/RootView.swift`、`App/AppEnvironment.swift`：Release 可用的依赖装配、账户退出取消任务。
- ChatFeature `ChatDependencies.swift`、`ChatView.swift`、`ChatViewModel+RoleplayContinuity.swift`：把学习卡片装配到正常聊天，接受的练习通过普通文字聊天 system context 注入，不注入语音通话。
- `DomainKit/Learning/LearningChatPresentation.swift`：提示节流、持久化已读、延后、好友风格练习提示词。
- 自动展开必须避开用户输入和 NPC 回复；每天最多2次，间隔至少10分钟。主动练习要用户接受。
- 普通观察4条消息或空闲90秒；活动练习使用12秒空闲窗口，且等正常聊天回复结束。检查4条消息快速达到批量阈值时是否应仍等待练习空闲窗口。
- 成功回顾与失败尝试分别计数：每天最多6批成功回顾、12次调用；后台回顾不扣用户可用积分。
- 成功但无能力证据也有反馈收据，避免用户不知道是否生效。
- 深色和超大字号已检查：固定图标尺寸，大字号两行标题、纵向按钮、卡片内部滚动。

### 评分与真实模型

- `DomainKit/Learning/LearningSystemPolicy.swift`：证据、等级、独立表达去重、间隔、跨设备合并；ruleRevision=4。
- `LearningSystemReviewer.swift`：严格四维评分、原文引用/支持项校验，拒绝练习、中英混写、撤回/修正、注入等逻辑。
- 新 `LLMTask.learningReview` 路由，2400 tokens；评估器最多2次尝试，LLMRouter 不额外隐式重试。
- 不要为了让真实模型通过而放松原文/语言/支持项验证；用真实样本定位误判并回归。

### 云端

- GET/PUT `/v1/learning/state`，认证、CAS revision、冲突重读重试、no-store。
- PostgreSQL authoritative；云同步 ledger 和已完成听力，未完成任务/待评估原文留本机。
- 同步开启状态不会自动替另一设备同意学习；当前 enabled 上传但不恢复，要保持清楚语义。
- 2MiB payload 限制：未来长期增长需检查，不能静默删历史。
- `Backend/src/modules/learning/`、迁移0026/0027、server装配、账户数据导出、admin学习回顾标签。
- 生产当前 `/opt/lingotrip/releases/20260923-learning-chat-v2`；DeepSeek `deepseek-v4-flash`，thinking关闭，2400 tokens、45秒、JSON支持。
- 后端 readiness/匿名401、路由数据库配置已验证；没有清除用户数据。
- 服务器 root@120.25.204.159，之前临时 SSH master socket `/tmp/lingotrip-learning-deploy-20260923.sock` 已失效。不要把历史口令/令牌写进交接、仓库或日志；需连接时检查现有安全连接方式。

## 验证结果：可复用，勿夸大

完整记录：[../verification/learning-production-20260923.md](../verification/learning-production-20260923.md)。其中早期 Pending gates 的“最终编译”已被后续记录完成，按末尾最新记录判断。

- 最新集成单测 **92通过、0失败、0跳过**：
  `build/DerivedData/VerificationResults/20260923T061219Z-73627.xcresult`
  `/tmp/learning-integrated-final.log`
  包括 LearningReviewQueueTests、LearningChatPresentationTests、LearningLedgerMergeTests、LearningSystemPolicyTests、LearningSystemReviewerTests、ChatWorkflowTests。
- 普通字号模拟器 UI：同意→练习→草稿→详情→返回→结束→延后通过：`20260923T060050Z-69716.xcresult`。
- 真正深色+最大辅助字号 UI 同路径通过：`20260923T061058Z-73109.xcresult`；截图已检查，位于 `/tmp/learning-dark-final-images/`。
- 最终 Release 模拟器编译成功，日志 `/tmp/learning-release-final.log`。
- `Scripts/preview.sh preview messages` 已安装启动最新 Debug 模拟器预览。
- 后端166通过、79环境门控跳过；隔离PostgreSQL CAS/并发/账户隔离/删除级联测试通过；typecheck、lint、架构检查通过。
- 隔离PG `/tmp/lingotrip-learning-pg-20260923`、端口55483，交接前已停止；无须删除。别碰别的数据库。

### 尚未通过的真机证据

- 真机测试 `build/learning-phone-round2-20260923.xcresult`，日志 `/tmp/learning-phone-round2.log`：App/runner安装成功，但运行器 `Timed out while enabling automation mode`，**未执行触屏用例，不能计为通过**。
- App直接启动成功。手机安装包早于最后一轮仅可访问性布局修正；下一轮重新构建安装。
- 补充真实模型8例评估，手机网络探测 -1009，前三例 -1005 后自动停止。报告 `/tmp/learning-live-dedicated-route.json`。**没有可用模型准确率结果**。
- 用户现在已说“好了，继续”，应重新验证上述阻塞。

## 设备和可执行命令

```sh
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
# 手机 iPhone13 / iOS27
xcrun devicectl device info lockState --device 00008110-00092C493C0B801E
# 模拟器 iPhone17 Pro / iOS26.1
# 47DD7BF7-5378-47D7-ACC3-792EF8AAFF11
```

复用 `build/DerivedData` 和 `build/SourcePackages`，不要创建重复巨大构建目录。最近空闲磁盘仅约1–2GB，构建前检查，若需清理只处理明确可重建的缓存，保留用户数据及验收证据。不要并行运行共用 DerivedData 的 Xcode构建。

真机 UI（结果路径用新的，避免已存在错误）：

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild \
  -project LingoTrip.xcodeproj -scheme LingoTripPerformanceTests \
  -configuration Debug -destination 'id=00008110-00092C493C0B801E' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=L28WGN9J8T RUN_LIVE_LEARNING_UI=YES \
  -only-testing:LingoTripUITests/ProductionLearningChatUITests/testLiveInlineLearningAndBurstRecovery \
  -resultBundlePath build/learning-phone-round3-20260923.xcresult test \
  > /tmp/learning-phone-round3.log 2>&1
```

`Tests/LingoTripUITests/ProductionLearningChatUITests.swift`：
- `testLiveInlineLearningAndBurstRecovery`：真实账号Ruby，开启/开始任务，连续3句发送、等待真实节奏、检查临时报错、详情。已有草稿会skip，避免把用户草稿发出去。
- **需要加强该用例**：现在主要检查无临时报错和页面可达，尚未严格断言真实回复与学习证据落库；固定回答也应与实际推荐任务匹配。不要把弱断言通过当完整验收。
- `testLiveDraftPreservationAndListeningExit`：草稿→详情→听力播放→退出→草稿。该用例尚未真机执行；目前会附加测试草稿，运行前改为妥善保留并恢复用户已有草稿。
- 两个offline用例是隔离内存预览，不能算真实模型验证。
- 真实测试 opt-in 来自测试bundle Info.plist `LingoTripLiveLearningUI=YES`，project.yml已配置。单测scheme是LingoTrip，UI scheme必须用LingoTripPerformanceTests。

补充真实模型评估（**不替代触屏E2E**，使用已登录手机、独立报告，不改学习成绩）：

```sh
xcrun devicectl device process launch --device 00008110-00092C493C0B801E \
  --terminate-existing --environment-variables '{"LINGOTRIP_LEARNING_V1_EVAL":"1","LINGOTRIP_LEARNING_V1_EVAL_GROUP":"edges","LINGOTRIP_LEARNING_V1_CASE_IDS":"fragments,split-reason,withdrawn-choice,refusal-after-answer,mixed-language-reason,complete-english-with-translation,romanized-chinese,comparison"}' \
  com.tiantian.lingotrip
xcrun devicectl device copy from --device 00008110-00092C493C0B801E \
  --domain-type appDataContainer --domain-identifier com.tiantian.lingotrip \
  --source Documents/learning-v1-evaluation.json --destination /tmp/learning-live-round3.json
```

评估实现 `App/LearningSystemLiveEvaluation.swift`、`LearningSystemEdgeSamples.swift`、`LearningSystemObservationSamples.swift`。不设 CASE_IDS 会跑整个选择组，先小批验证联网/新路由，再扩样；三次连续错误会提前停止。报告检查 startedAt/complete，不能误读旧报告。另有 `LearningSystemFlowEvaluation.swift` 真实ChatViewModel链路，但依然不是触屏测试。

标准测试和预览：

```sh
Scripts/test.sh -only-testing:LingoTripTests/LearningReviewQueueTests \
  -only-testing:LingoTripTests/LearningChatPresentationTests \
  -only-testing:LingoTripTests/LearningLedgerMergeTests \
  -only-testing:LingoTripTests/LearningSystemPolicyTests \
  -only-testing:LingoTripTests/LearningSystemReviewerTests \
  -only-testing:LingoTripTests/ChatWorkflowTests
Scripts/test-ui.sh -only-testing:LingoTripUITests/ProductionLearningChatUITests/testOfflineLargeTextDarkInlineFlow
Scripts/build.sh -configuration Release
Scripts/preview.sh preview messages
```

Computer Use 的 Device Hub (`com.apple.dt.Devices`) 之前反复超时；不要无限重试。优先真实XCTest，导出截图/AX逐个查看。`xcresulttool export attachments`、`get test-results summary/tests` 可定位失败。日志中的simctl诊断失败不一定是用例失败原因，应读xcresult断言。

## 下一轮执行顺序与扩样重点

1. 查工作区、后台残留进程、磁盘、手机连接和解锁；用户已准备，直接重试最新真机测试与真实模型小批。
2. 若通了，先完成正常聊天→可选练习→真实答复→反馈→证据→重启仍保留这一闭环，并检查没有重复追问、假即时回复、额外打字等待或取消报错。
3. 记录逐轮样本、步骤、预期、实际、截图、模型输出/耗时、修复提交和回归结果。每轮测之前未覆盖的部分，发现问题就修复并重跑受影响路径。
4. 交互：连发/中途继续打字、修改/撤回答案、拒绝或转话题、切角色/页面、后台返回/锁屏、草稿、键盘和翻译面板高度、卡片展开收起、快速重复点击、暂停/恢复、日期和每日上限、错误重试/恢复、深浅色/大字/小屏。
5. 量化：短句/碎片/错拼也可表达成功；纯问候无机会不记零；代词有无上下文、第三人称引用、跨句原因、撤销与修正、中英混写/拼音、提示注入、辅助表达不冒充独立能力、重复刷分、同日与跨日证据、不同话题迁移、确认冷却、过期证据、听力多次播放/退出/断音/交卷/复习。
6. 数据：断网后队列保留、失败不消费成功批限额、关闭学习取消回顾、退出/换账号隔离、CAS冲突与删除不复活、历史版本/时钟倒退、长期记录增长。
7. 特别待审：练习长期不结束是否应过期；推荐题库耗尽与被冷却目标的回退；卡片错误全局/按角色归属；云端限额是否应跨设备统一；completed listening 同ID冲突；2MiB容量。先证据后改，别堆功能。
8. 完成逻辑变更定向提交；更新验收记录；安装最新手机和模拟器版本。存在未完成真机项则如实保留，不称“可上线、完全无bug”。

## 17:50 后续进度（阅读时以本节与验收记录末尾为准）

- 真机已解锁、联网，XCTest 自动化可执行。修复测试 bundle 的 opt-in 读取后，正常聊天内开启练习、三句连发、真实 Ruby 回复、学习反馈、独立证据及 10 XP 的触屏闭环通过。证据 `build/learning-phone-round8-20260923.xcresult`，但该轮耗时约 227 秒；原因未定。测试账户当天已达 12/12 回顾请求上限，不得清零续测。
- 真机草稿→学习详情→项目 TTS 播放中退出→返回聊天，草稿保持且临时草稿清理通过：`build/learning-phone-listening-round1-20260923.xcresult`。完整播放、答题交卷及中断恢复仍待测。
- 随后真机完成首题两次完整 Supertonic-3 播放，答题选项按规则解锁，退出重进仍为 2/2；没有选择答案或生成听力成绩。修正解锁态样式后视觉复测通过：`build/learning-phone-listening-round3/4-20260923.xcresult`。交卷、跨日复习及系统中断仍待测。
- 真实模型独立评估：显式任务 47/47、普通观察 31/31，预期技能和暂停标志一致；报告 `/tmp/learning-live-all-edges-final-r2.json`、`/tmp/learning-live-observation-final-r2.json`。这些不更改学习 ledger，也不替代真机触屏。
- 已修复显式任务评分提示遗漏 rubric 导致的循环理由、无关反思和简洁澄清误判；无任务观察现选最高完整满足的档位。选中练习达到 4 条时仍等待 12 秒安静窗口。好友聊天提示避免把自然答复称作作业；隔离真实 ChatViewModel 重新验证通过，报告 `/tmp/learning-flow-round12.json`。
- 最新 Xcode-hosted 集成测试 93 通过、0 失败、0 跳过：`build/DerivedData/VerificationResults/20260923T095908Z-97443.xcresult`。听力视觉修正后的最终 Release 构建及 `Scripts/preview.sh preview messages` 已完成；最新 Debug 版本也已安装真机。定向提交以 Git 状态为准。
- 接下来：UTC 次日额度恢复后验证新提示的真实触屏回复和 4 条连发等待；扩展错误恢复、听力交卷与系统中断、跨设备冲突及长期增长测试。不要把有限测试描述为全面上线验收。
