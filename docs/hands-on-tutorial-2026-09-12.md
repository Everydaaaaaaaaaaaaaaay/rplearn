# 选角后的上手练习：复用正式界面

## 界面与引导

选角后进入教程；完成或跳过才保存正式旅伴。设置中的“上手练习”只打开可随时关闭的练习，不重新选人。

App/ProductionTutorialView 在组合根装配正式 ChatFeature.ChatView 和 HomeFeature.ActivitiesView。OnboardingFeature 只接收 TutorialPresenter，不导入其他 Feature。旧独立教学聊天/外出页面已删除。

聊天的导航栏、消息列表、输入栏、长按菜单、查词浮窗全部来自正式 ChatView。外出直接复用 ActivitySceneView、ActivityActionView、ActivityJourneyCoordinator 和 SocialEncounterModel：实拍场景热点 → 准备页 → 出发动画 → 剧情翻页 → 两次选择 → 加好友/告别。短提示可折叠，下一阶段重新展开。练习的出行动画仍使用正式播放器，仅缩短为 1.5 秒；不等待网络生成。

咕咕和嘎嘎的“咕/嘎”直接接在句尾，标点之前，不用逗号或独立短句隔开。文案按当前场景/剧情状态调整，不教学用户应该怎样聊天。

## 数据隔离

每次打开创建独立 inMemory ModelContainer。聊天、好友、收藏、资产和记忆的 stores 全部来自该容器；不会传入正式账号的 stores、BackendClient 或生产 LLM。唯一真实写入是首启最后保存选定旅伴的原有完成回调。重玩完成回调只有 dismiss。

教程用本地 LLM adapter 提供固定练习回复，其他 AI 请求不联网。初始句翻译预置；不会为任意输入伪造译文。词典例句优先读取开场演示词的预置译文；其余例句使用 Apple 本地翻译兜底，不调用付费 AI。语言包未就绪时，用户点重试可触发系统语言准备流程。录音和实时通话不在本教程开放，避免媒体文件与外部权限流程；正式聊天不受影响。

Home 的教程配置确保不调用 NPC 注册/选人服务、不 reserve/complete ActivityEncounterHistory，也不读写 ActivityJournal。练习加好友调用正式 RosterStore.makeFriend，但仅操作内存容器。各场景使用本地短分支文本，呈现、选择和结束的状态机与正式功能一致。

练习 NPC 使用 Elliot Shaw 的既有头像，源 Assets/NPC/Library/v3/images/npc-0007.png，复制为 App/Resources/tutorial-elliot.png；与正式选定旅伴区分，无远程头像下载。

## 语音修复

旧版自己创建 AVSpeechSynthesizer，绕过正式 AudioSessionCoordinator；已移除。整句和词典读音均通过正式 SpeechService / AdaptiveSpeechService，使用 Supertonic 与系统回退以及现有播放会话管理。教程退出/换阶段停止播放。

UI 测试监听 SpeechKit 的 speechPlaybackDidBegin（系统 didStart 或 PCM 播放开始），分别确认整句和单词两次点击实际进入播放；没有用点击成功冒充发声，也没有验证手机扬声器的物理音量。

## 验证

20260912T134234Z-31687：正式聊天长按翻译、整句播放、单词查词与播放、场景热点、出发、两轮剧情选择、练习加好友和设置重玩均通过；已检查三张正式界面截图。

新配置默认 nil，正式 Chat/Home 路径维持原有行为与 15 秒过场。无后端部署。

20260912T134824Z-33088：iPhone SE 深色完整教程（含两次实际音频开始事件）、跳过与保存失败重试 3 项通过；检查了热点、独立头像与结束菜单截图。场景媒体未修改，沿用 Assets/Activities/RealMotion-v5/acceptance-v5.md 的既有范围和未验证项；本轮仅验证教程容器的裁切与热点操作，不新增媒体循环验收结论。
