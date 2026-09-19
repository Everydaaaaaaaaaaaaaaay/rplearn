# 教程浮层与相遇自动朗读验收 · 2026-09-19

## 实现范围

- 开场与相遇统一 `TapToContinueHint`，开场显示“轻点空白继续”。
- 教程复用完整 ChatView/ActivitiesView，不再有顶部练习栏、底部继续或跳过单步。窄版吉祥物提示在中上区域浮动，依据目标位置避让；输入、查词、语法、设置、通话/足迹子页暂时隐藏引导并暂停自动进度。目标呼吸高亮、吉祥物轻微浮动与内容淡入淡出支持 Reduce Motion。
- 移除固定回复及电话/录音的无操作分支；真实聊天使用现有模型路由和正式投递流程，教程回复不等待 NPC 下次上线。
- 五条额度由工作区共享，覆盖文字、录音、通话、重开聊天，落库失败退还名额。第六条不写入、不请求回复、保留草稿。删除好友在界面与模型层保护。
- `DSQuickNotice` 统一两秒、不阻塞操作、图上文下、微圆角、自适应系统外观的短提示；规范登记于 `docs/design-system.md`。
- 相遇默认开启自动朗读；`SpeechPlaybackQueue` 从 ChatFeature 移至 SpeechKit，聊天与相遇共用同一 FIFO/停止屏障，快速推进不会取消上一段。
- 聊天、记忆、好友、收藏仍使用临时内存容器；活动足迹使用独立临时 suite，结束清理；本地录音不上传，结束清理。真实 AI 推理会产生正常服务请求/用量记录。

## 单元回归

Xcode-hosted、现有 iPhone 17 Pro 模拟器，`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer`。

1. `Scripts/test.sh -only-testing:LingoTripTests/ChatWorkflowTests -only-testing:LingoTripTests/ChatAutoReadQueueTests -only-testing:LingoTripTests/EncounterChapterTests -only-testing:LingoTripTests/SocialEncounterDiversityTests`：36 通过、0 失败。证据 `build/DerivedData/VerificationResults/20260919T121507Z-72697.xcresult`。
2. 新增失败落库退款测试及教程额度/好友保护复核：2 通过、0 失败。证据 `20260919T121942Z-74893.xcresult`。该命令中未匹配的 ActivityJournalTests 不计入覆盖。
3. `ActivityJourneyTests/testAllBranchesPreserveContextAndAreIdempotent`、`testSocialRecordRetainsIdentityAndActualReplyWithoutBreakingLegacyRecords`、`testIncompleteOrCorruptDataNeverOverwritesHistory`：3 通过、0 失败。证据 `20260919T122105Z-75815.xcresult`。

共 40 个不同的相关单元测试通过。生产 ViewModel + 真正 SwiftData 内存 stores 的测试验证上下文回复、五条上限、跨页面/输入方式保护、草稿保留、删除好友拦截；测试替换外部服务，不调用付费线上模型。

## UI 路径和外观

使用 `Scripts/test-ui.sh` 定向运行 `OnboardingWelcomeTests`：

- `testOpeningChoicesAppearAsMessagesAndReachSelection`：开场剧情到选角通过（`20260919T120847Z-71082.xcresult`，该轮另外两项旧测试定位失败，后续已修正）。
- `testHandsOnTutorialUsesLocalTranslationDictionaryAndEncounter`：长按翻译 → 查词/读音 → 点外侧关闭 → 自动进入活动 → 相遇选择 → 默认自动朗读及开关 → 加好友 → 自动完成。
- `testTutorialExplorationKeepsControlsAndProtectsFriend`：完整聊天设置、保护好友两秒提示、语音输入切换、打开真实通话页并返回。
- `testTutorialSixthMessageShowsBriefNoticeAndKeepsDraft`：浅色/键盘打开情况下发送五条，第六条显示标准提示，消失后草稿仍在。

后三项 3 通过、0 失败：`20260919T121734Z-74140.xcresult`。已检查保留截图：浅/深色浮层、目标气泡高亮、相遇控制区、两种限制提示、真实通话页。首次测试定位失败分别是词典关闭入口并非可见按钮、挂断有两个同名入口；修正为点词典外侧与明确定位后通过，未改产品绕过断言。

这些结果验证了 UI 路径、临时存储与队列行为；没有把模拟器截图当作真机扬声器或真实模型回复质量验收。场景媒体本身未修改，沿用原验收记录。

最后一次调整后的完整教程与自由探索复核：`20260919T122214Z-76075.xcresult`，2 通过、0 失败（上述路径重跑，不重复计数）。
