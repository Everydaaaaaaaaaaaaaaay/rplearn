# 透明描边胶囊按钮 v5

2026-11-14，Codex 自检。本版按用户要求修改全屏场景底部主按钮，采用白色文字、1pt 白色胶囊描边，内部透明。继续外出状态使用同一按钮外观。

## 范围与沿用

- 照片、构图、字号、间距与二级面板沿用 [v4](acceptance-v4.md)。原图地理、空间、许可和媒体哈希沿用 v2。
- 透明按钮使用 `contentShape(Capsule())` 覆盖完整胶囊内部，点击描边内的留白区域可触发操作。
- 本版检查按钮的透明显示、白字与描边可读性、命中区域及小屏辅助字号。场景媒体为静态照片，动态证据沿用 v3/v4。

## 本版证据

- 标准屏 `build/DerivedData/VerificationResults/20261114T071501Z-48407.xcresult`，1 项通过。覆盖手势与箭头切换、按钮目标一致，以及点击胶囊左侧内部留白。泰晤士河南岸与博罗市场的原生截图位于 `build/ActivityWorldPhotos/fullscreen-v5/standard/`，已观察描边内照片连续可见、白色文字与细线完整。
- 小屏 `build/DerivedData/VerificationResults/20261114T071655Z-48920.xcresult`，iPhone SE 3、iOS 27.0，1 项通过。最大辅助字号下按钮完整可点，长标题与箭头分离，三处/五处末项可达。原生截图位于 `build/ActivityWorldPhotos/fullscreen-v5/compact/`，已观察南岸与博物馆场景的透明按钮、白字及边界。
- iOS 架构与 diff 检查通过。

## 结论与边界

透明描边按钮的本机预览可交付。已通过 `Scripts/preview.sh preview scenes-preview` 安装最新构建并留在 iPhone 18 Pro。正式世界与真机验收边界继续见 v4。
