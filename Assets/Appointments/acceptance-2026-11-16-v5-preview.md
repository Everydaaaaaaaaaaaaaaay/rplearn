# 回顾页 v5 原生方案预览

2026-11-16，交付范围为一张 SwiftUI 原生回顾页预览图。预览入口为 Debug 的 `appointments-preview`，场景 `summary-design`，使用隔离的本地演示服务。

## 界面与数据

采用连续暖白正文、148pt 城市照片区、22pt 标题、48pt Oliver 头像、爱心好感图标、用户头像和书签记忆图标。照片、头像、字体、图标与按钮均由当前 iOS 项目实际渲染。

演示数据通过既有本地服务的开始、双语自定义行动和结束命令生成。两次选择及完整结果均显示，与 v4 完整流程截图中的内容一致。头像复用 `AvatarBadge` 与 `avatar_oliver`，用户头像采用 `UserAvatar` 的本地默认呈现。

摄影来源、许可和原图证据沿用 [v4 记录](acceptance-2026-11-15-v4.md)及其引用记录。新增 148pt 横幅裁切已在最终原生截图核对，照片主体、导航和正文边界可读。G0–G3 证据沿用，G4/U1 本版范围为标准屏预览。

## 原始截图

设备为 iPhone 18 Pro，402×874pt，截图为 1206×2622px。截图直接导出自原生 UI 测试附件，交付文件逐字节一致。

- 原图 `build/appointment-summary-design-2026-11-16/final/009A5F5D-7C18-4A1E-A7E5-7AE4DE23BE6B.png`。
- 交付文件 `/Users/tiantian/.codex/visualizations/2026/10/30/01a18d7d-7164-7210-9727-87e9e78447ef/appointment-summary-native-2026-11-16.png`。
- SHA256 `5efc09095cd3a19b4f3577fefa73c55062b01482ff41a640f1e9f0f6c4e883cd`。

## 验证

原生定向 UI 测试 1 项通过，0 失败，0 跳过。检查标题、好感与两次已接受的本地演示选择并截取首屏。结果包 `/Users/tiantian/eng/build/DerivedData/VerificationResults/20261116T070850Z-54011.xcresult`，日志 `build/appointment-summary-native-preview-final.log`。

构建、`Scripts/check-architecture.sh --ios` 与 `git diff --check` 通过。Computer Use 查看了 Device Hub 中实际运行的原生预览，最终双语数据版本再次核对完整截图。通过 `Scripts/preview.sh` 安装并打开该预览场景，留在主设备模拟器。

本版为 Debug 视觉预览。正式业务接入、真机、窄屏和辅助字号属于后续实现的验证范围。
