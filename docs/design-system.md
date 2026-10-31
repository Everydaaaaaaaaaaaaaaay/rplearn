# 设计基础

LingoTrip 的界面以旅途场景和角色关系为主，UI 提供清晰层级，不用统一卡片覆盖所有页面。

## 原则

- 优先使用 SwiftUI/UIKit 原生导航、Tab、菜单、Sheet、滚动和辅助功能行为。
- 高频反馈短促克制；明显弹跳只用于奖励、确认等低频时刻。
- 页面构图和业务组件留在对应 Feature。
- 多个 Feature 稳定复用的视觉或行为原语再进入 `DesignSystem`。

## DesignSystem 内容

- `Tokens/`：语义颜色、间距、圆角、动画和城市场景色板。
- `Styles/`：表面、按钮和按压反馈。
- `Components/`：HUD、模态框、头像、标签、消息气泡和旅行转场。
- 根目录：触觉、富文本、布局等基础能力。

`DSSurface` 只表示空间层级：

- `.grouped`：页面内分组。
- `.elevated`：独立内容。
- `.floating`：场景上方的关键内容。

场景大图、剧情卡和活动 Hero 自己定义构图，不套通用表面。

新增组件时优先复用现有 token，同时保留 Dynamic Type、Reduce Motion、降低透明度和
VoiceOver。无需为了减少少量 SwiftUI 代码创建万能组件。

## 快速反馈与教学浮层

短暂、无需用户确认的操作反馈统一用 `DSQuickNotice` / `.dsQuickNotice`：SF Symbols 单色图标在上，文字在下；12pt 微圆角方框、系统自适应材质，淡入淡出，停留 2 秒，再次触发重新计时。不得用阻塞式 alert 替代这类轻反馈；新增语义图标加入 `DSQuickNotice.Symbol`。

`TapToContinueHint` 统一剧情的弱继续提示。`tutorialFocus` 仅覆盖呼吸描边、不改变布局或截获手势，并通过 `TutorialTargetPreference` 上报目标位置供指引避让。教程指引不能用 safe-area inset 挤压正式界面。

## 统一视觉实施基准

用户已于 2026-10-31 确认按[原生设计方向](design/unified-native-2026-10-31/README.md)统一现有界面。
共享语义色、纸面、选择、行和底栏已接入正式 DesignSystem；新增页面优先使用
`DSReadingPalette`、`DSPaper`、`DSReadingChoice`、`DSReadingRow` 与 `DSActionButtonStyle`。

活动系统已重构，原设计稿的动作菜单由真实地点列表与外出阅读取代。
[正式接入记录、当前结构与验证范围](design/unified-2026-10-31/implementation.md)是新版活动的界面依据。
原设计夹具中的示例计数与未实现的赴约功能不进入正式业务。
