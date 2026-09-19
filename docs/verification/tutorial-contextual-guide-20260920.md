# 教程引导修复 · 2026-09-20

## 改动

- 高亮改为沿 MessageBubble 的真实表面和 UnevenRoundedRectangle 绘制，不再用文字区域外扩估算；出发按钮使用胶囊高亮。
- 教程提示使用更透明的 ultraThinMaterial，位置根据当前目标 anchor 自动切换上下；聊天气泡上方留出时间标签空间。
- 朗读步骤需要翻译完成后手动点击消息菜单「播放」，不再仅因翻译完成而倒计时跳过。自动播放/单词发音事件不能代替该操作。
- 活动页提示「行动」，选中后准备页单独提示「出发」；活动页非入口区域加 48% 暗遮罩，入口保持原亮度。
- 相遇继续、选项与结束操作发布定位锚点；教程选项/结束区前按引导实际高度预留滚动空间，避免提示覆盖正文。正式非教程页面空间为零。

## 验证

Xcode 托管 UI 测试 `OnboardingWelcomeTests/testTutorialGuideWaitsForPlaybackAndFollowsTargets` 完整通过：
`build/DerivedData/VerificationResults/20260919T222011Z-1822.xcresult`。
覆盖翻译后静置 3 秒仍停留朗读提示、手动播放后切换、提示邻近消息、查词关闭、选择行动与出发文案拆分、相遇选项、加好友完成。
审看附件：tutorial-production-chat / activities / departure / encounter（iPhone 17 Pro，iOS 26.1，深色）。
此前布局测试也通过，但截图发现结束页遮挡末句，新增动态预留空间后以上述最终结果为准。

## 未通过及限制

原真实音频集成测试保留。当前模拟器曾因 AURemoteIO RPC 超时 SIGABRT，重建 SimAudioProcessorService 后仍出现音频开始通知超时及 stopSpeaking 等待。
没有把音频检查改判通过，也没有改变正式语音服务。布局测试通过 DEBUG 专用 `UI_TEST_TUTORIAL_SILENT=1` 注入静音 SpeechService；原集成测试继续用真实服务。
本轮未进行真机、浅色与超大字号视觉复测。场景素材未变，本次仅验证教程遮罩和布局，不扩展已有场景真实性验收结论。
最新 Debug 已通过 Scripts/preview.sh 安装供查看。
