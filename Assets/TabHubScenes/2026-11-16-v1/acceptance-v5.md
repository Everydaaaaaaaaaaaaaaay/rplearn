# 活动首页左下按钮对齐 v5

2026-11-17，根据用户对 v4 的反馈，将“出去走走”胶囊恢复到卡片左下方。城市名以胶囊的实际宽度居中，较长的城市名可向两侧延展。读取胶囊的实际布局宽度，用它设置城市名与停留提示的承托宽度。

世界地图标题改用 Dynamic Type 的 `title3`、中等字重，默认字号从 17pt 提升至 20pt，并收紧标题与箭头之间的横向间距。

本版替代 [v4](acceptance-v4.md) 的按钮位置与地图字号验收。摄影证据引用 [v1](acceptance-v1.md)，玻璃材质引用 [v2](acceptance-v2.md)，我的页入口见 [v3](acceptance-v3.md)。G0–G2 沿用已有证据，G3 不适用。

## 原生验证

初轮 Grid 实现在曼彻斯特将胶囊右推约 9.7pt，左缘位置断言检出该问题。改为读取胶囊实际宽度后重新验证，最终证据采用下列复验结果。

- 标准屏使用 iPhone 18 Pro、iOS 27.0、402×874pt。`TabHubTests/testHeaderContrastAndDarkAppearance` 1 项通过、0 失败、0 跳过，覆盖开普敦、曼彻斯特、纽约、悉尼浅色与伦敦深色。
- 测试新增胶囊左缘距应用左侧 40pt 的断言，对应卡片外侧 16pt 与内部 24pt，允许 1pt 栅格误差。城市名和胶囊中心相差不超过 1pt。两字与四字城市名均通过。
- 标准屏结果包为 `build/DerivedData/VerificationResults/20261117T061659Z-90024.xcresult`。原生截图及 XCTest 导出清单位于 `build/home-button-alignment-20261117/standard/`。Computer Use 已查看曼彻斯特浅色与伦敦深色首页，胶囊恢复左下位置，城市名以胶囊宽度居中，放大的地图标题完整可读。

- 小屏使用 iPhone SE 3、iOS 27.0、375×667pt。`TabHubTests/testHubRoutesAndPhotoCredits` 与 `testAccessibilityLayouts` 共 2 项通过、0 失败、0 跳过，普通字号与最大辅助字号均通过左缘位置及中心对齐断言，城市活动和地图入口可到达。
- 小屏结果包为 `build/DerivedData/VerificationResults/20261117T062704Z-91636.xcresult`。截图与导出清单位于 `build/home-button-alignment-20261117/small/`。Computer Use 已查看普通字号首屏、滚动后的地图，以及最大辅助字号首屏和底部。地图四字在默认和大字号下完整显示，箭头与标题之间有间距。

## 结论与交付

G4 通过本记录列出的模拟器、外观和字号范围。初轮 Grid 版的按钮偏移已通过最终复验关闭。本轮为离线模拟器验证。

`Scripts/check-architecture.sh --ios` 和差异检查通过。使用 `Scripts/preview.sh preview home` 安装最新构建，保留活动首页供查看，原生截图为 `build/home-button-alignment-20261117/preview-home.png`。
