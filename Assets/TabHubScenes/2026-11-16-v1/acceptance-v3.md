# 我的页入口精简 v3

2026-11-17，移除我的页的记忆档案入口。金币、AI 积分行采用只读展示，取消箭头和跳转，保留余额加载与下拉刷新。删除 AI 积分详情页及个人资料中的积分明细区块。聊天与语音原有的用量入口改为“查看会员订阅”，由组合根展示现有订阅页面。

摄影来源与原图证据引用 [v1](acceptance-v1.md)，玻璃材质和明暗外观证据引用 [v2](acceptance-v2.md)。本版复核入口精简后的布局和交互，G0–G2 沿用已有证据，G3 不适用。

## 原生验证

- 标准屏为 iPhone 18 Pro、iOS 27.0，402×874pt。`TabHubTests/testHubRoutesAndPhotoCredits` 与 `testAccessibilityLayouts` 均通过，0 失败、0 跳过。结果包为 `build/DerivedData/VerificationResults/20261117T051229Z-80609.xcresult`。
- 小屏为 iPhone SE 3、iOS 27.0，375×667pt，同两项测试通过，0 失败、0 跳过。结果包为 `build/DerivedData/VerificationResults/20261117T051540Z-81675.xcresult`。
- 两种屏幕均验证记忆档案入口已移除，金币与积分为独立的非按钮无障碍元素，点击后仍停留在根页。个人资料、收藏夹和设置入口均可使用。最大辅助字号下金币与积分可通过滚动到达。
- Computer Use 已查看标准屏和小屏的普通字号余额页、最大辅助字号首屏与底部原生截图。金币与积分右侧无箭头，数值和加载失败状态文字可读。截图及 XCTest 导出清单位于 `build/my-page-simplification-20261117/standard/` 与 `small/`。
- 资料与会员订阅往返、资料头像入口、资料/订阅/收藏/设置四处原生返回按钮和左缘滑动返回均通过定向测试。`MyPagePerformanceTests/testAccountSubscriptionAndReadOnlyBalances` 与 `TabSceneTransitionTests/testMePagesUseNativeBackAndEdgeSwipe` 共 2 项通过，0 失败、0 跳过。结果包为 `build/DerivedData/VerificationResults/20261117T051939Z-82721.xcresult`，截图位于 `build/my-page-simplification-20261117/routes/`，Computer Use 已查看资料页及订阅页原生截图。

## 交付与边界

G4 通过上述模拟器、浅色外观与字号范围。验证使用离线内存预览，AI 积分显示读取失败占位。聊天/语音到会员页的接线通过编译和源代码检查，线上额度触发链路、扣费与订阅购买属于未实测范围。

`Scripts/check-architecture.sh --ios` 与差异检查通过。通过 `Scripts/preview.sh preview me` 安装最新构建后保留我的页供查看，原生截图为 `build/my-page-simplification-20261117/preview-me.png`。
