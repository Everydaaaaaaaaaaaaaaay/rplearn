# 我的页设置入口行 v6

2026-11-17，设置入口移到收藏夹下方，与收藏夹组成一个磨砂玻璃分组。入口使用与其他行一致的齿轮图标、“设置”文字和右侧箭头。顶部标题采用无操作按钮的 `DSHubHeader`，移除右上角独立齿轮。

摄影证据引用 [v1](acceptance-v1.md)，玻璃材质引用 [v2](acceptance-v2.md)，我的页余额与入口精简见 [v3](acceptance-v3.md)，活动首页排版见 [v5](acceptance-v5.md)。本版复核设置入口及顶部标题，G0–G2 沿用已有证据，G3 不适用。

## 原生验证

- 标准屏使用 iPhone 18 Pro、iOS 27.0、402×874pt。`TabHubTests/testHubRoutesAndPhotoCredits` 1 项通过、0 失败、0 跳过。验证设置入口唯一、位于收藏夹下方、整行宽度超过屏宽的 80%、高度至少 60pt，并可进入设置页。
- 结果包为 `build/DerivedData/VerificationResults/20261117T064035Z-94304.xcresult`。截图及导出清单位于 `build/me-settings-row-20261117/standard/`。Computer Use 已查看我的页原生截图，顶部为居中标题，设置以普通入口行呈现，文字和箭头完整可读。

- 小屏使用 iPhone SE 3、iOS 27.0、375×667pt。最大辅助字号下 `TabHubTests/testAccessibilityLayouts` 1 项通过、0 失败、0 跳过。设置行可滚动到达，点击进入设置页，原生返回可恢复我的页，余额区域也可继续滚动到达。
- 小屏结果包为 `build/DerivedData/VerificationResults/20261117T064356Z-95114.xcresult`，截图及导出清单位于 `build/me-settings-row-20261117/small/`。Computer Use 已查看设置行的大字号截图，图标、文字、箭头完整，分组与相邻卡片有明确间距。

## 结论与交付

G4 在本记录的浅色模拟器与字号范围内通过，摄影和材质证据沿用已有记录。本轮采用离线预览。

`Scripts/check-architecture.sh --ios` 与差异检查通过。通过 `Scripts/preview.sh preview me` 安装最新构建并保留我的页，截图为 `build/me-settings-row-20261117/preview-me.png`。
