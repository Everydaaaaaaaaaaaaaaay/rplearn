# 活动首页入口排版 v4

2026-11-17，城市活动卡片的城市名、上次停留提示与底部胶囊采用同一水平中心线，按钮统一为“出去走走”。世界地图卡片删除城市数量文字，标题与斜向箭头图标位于卡片底部。

摄影来源及原图证据引用 [v1](acceptance-v1.md)，玻璃材质与明暗外观证据引用 [v2](acceptance-v2.md)，我的页入口精简见 [v3](acceptance-v3.md)。本版检查活动首页的排版与入口，G0–G2 沿用已有证据，G3 不适用。

## 原生验证

- iPhone 18 Pro、iOS 27.0、402×874pt，通过 `TabHubTests/testHeaderContrastAndDarkAppearance`，1 项通过、0 失败、0 跳过。覆盖开普敦、曼彻斯特、纽约、悉尼浅色与伦敦深色，断言可见按钮文案及城市名和按钮的水平中心相差不超过 1pt。结果包为 `build/DerivedData/VerificationResults/20261117T054756Z-85831.xcresult`。
- 标准屏截图与 XCTest 导出清单位于 `build/home-entrance-layout-20261117/standard/`。Computer Use 已查看曼彻斯特浅色和伦敦深色的原生首页，四字城市名和两字城市名均位于按钮正上方，世界地图卡片显示标题与箭头。

- iPhone SE 3、iOS 27.0、375×667pt，通过 `TabHubTests/testHubRoutesAndPhotoCredits` 与 `testAccessibilityLayouts`，2 项通过、0 失败、0 跳过。小屏普通字号和最大辅助字号均断言城市名与按钮共用水平中心，城市活动、赴约、照片许可等入口可进入并返回。
- 小屏结果包为 `build/DerivedData/VerificationResults/20261117T055122Z-86632.xcresult`，截图及导出清单位于 `build/home-entrance-layout-20261117/small/`。Computer Use 已查看普通字号首页、最大辅助字号首屏和底部，城市名与胶囊居中，大字下可滚动到世界地图，卡片显示完整标题。

## 赴约卡片信息核对

`HomeView.reloadAppointment()` 读取已登录账号的约会，`HomeHubPresentation.nextAppointment(in:)` 优先选进行中的一项，其次选有效已确认约会中开始时间最近的一项。卡片展示旅伴头像、带人物名的约会标题、北京时间、城市和地点，点击后传入该约会 ID。读取失败时显示更新失败提示。本轮通过现有接线与模型实现核对这些行为，预览使用无约会的离线账号。

## 结论与交付

G4 在本记录的模拟器、外观和字号范围内通过。本轮使用离线预览，已有线上约会数据的展示属于代码核对范围。

`Scripts/check-architecture.sh --ios` 与差异检查通过。使用 `Scripts/preview.sh preview home` 安装最新构建，保留活动首页供查看，截图为 `build/home-entrance-layout-20261117/preview-home.png`。
