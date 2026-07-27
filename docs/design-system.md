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
