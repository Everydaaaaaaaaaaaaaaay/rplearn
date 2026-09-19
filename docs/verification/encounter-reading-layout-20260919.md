# 相遇阅读布局修复 · 2026-09-19

范围：ActivityActionView；未修改场景图片、影片或数据/后端。

- 准备页复用当前活动场景的模糊背景，固定浅色纸面承托深蓝文字，解决深色模式对比度问题；出发按钮按内容收窄并居中。
- 人物卡移出滚动区域，头像 52pt、内边距 16pt；删除相遇标语，标题移入剧情面板。滚动视口顶部 22pt 渐变遮罩使剧情接近人物卡时淡出。
- 英文单击查词；继续手势仅挂在背景层，避免祖先手势抢占词按钮。译文匹配对应原文字号、字重与行距。
- 自动朗读固定 speaker.wave.2.fill 图形，关闭时 0.2s 渐变灰色；减少动态时不动画。

## 验证

iPhone 17 Pro / iOS 26.1 模拟器，Xcode 托管 UI 测试：

- testPreparationIsCentered
- testChapterSupportsWordLookupAndVoice
- testEncounterTranslationWholeChoicesAndScrolling
- testEncounterAppearance

首轮 4 通过，0 失败：`build/DerivedData/VerificationResults/20260919T152003Z-92786.xcresult`。
补充人物卡纵坐标/高度不变及朗读关闭仍可点的断言后，滚动测试再次通过：
`build/DerivedData/VerificationResults/20260919T152318Z-93535.xcresult`。

人工审看附件：深色准备页、深浅色剧情初始页、雨天咖啡馆翻译选项及关闭朗读状态。
确认文字清晰、按钮紧凑居中、卡片固定、滚动顶部渐隐、灰色朗读图标仍可见。
查词测试确认单击 map 弹出释义且不增加下一段；空白边缘点击及选项触发分别验证。

仅验证本次 UI 与已有背景组合；沿用场景原始验收记录（`docs/activity-scene-visual-acceptance.md`），不新增素材真实性/动态验收结论。
未进行真机、小屏与超大辅助字号的本轮视觉复测。最新 Debug 使用 Scripts/preview.sh 安装至当前模拟器。
