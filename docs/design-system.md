# 设计基础

## 蓬蓬（Puff）设计系统 · 2026-11-21 起

面向儿童与青少年、成人也适用的新设计系统。信息页、联系人页已完整迁移；其余页面仍使用下方旧 `DS*`
令牌，迁移时整页替换，不在同一页面混用两套表面。源码在
`Packages/LingoKit/Sources/DesignSystem/Puff/`。

### 原则

- **少说明**：界面只放标题、状态、数字和必要的错误提示，不加解释功能或规则的副文案；
  需要的补充信息放进 VoiceOver 标签。
- **白色为主基调**：页面纯白，深色模式为柔和夜空蓝 `#161A2E`，不用纯黑。
- **糖果色只做点缀**：`PuffCandy` 六色（sky、bubblegum、sunny、mint、grape、tangerine），每色含
  `base` 填充、`deep` 白底上的图标与强调字、`wash` 浅底、`lip` 实心按钮唇边。正文始终用 `Puff.Palette.ink`。
  同一位朋友的颜色由名字稳定决定（`PuffCandy.stable(for:)`）。
- **圆润**：全部使用圆体 `Font.puff(_:_:)`，跟随动态字体；圆角 12 / 18 / 24 / 30。
- **厚卡片**：白色正面 + 细描边 + 底部 4pt 唇边（`puffCard`、`PuffCardButtonStyle`），按下时正面陷进唇边，
  松手轻弹回来。小按钮用 `PuffSquishButtonStyle`，分组内的行用 `PuffRowButtonStyle`。
- **灵动但可打断**：`Puff.Motion` 全部是弹簧。首屏用 `puffEntrance(index:isShown:)` 逐行错峰弹入，只播放一次；
  角标、星星用 `.puffPop`；展开内容用 `.puffDrop`。“减弱动态效果”时统一降级为短淡入淡出，逐帧动画暂停。
- **卡通代替实拍**：`PuffCityScene` 用 Canvas 程序化绘制 15 座城市的卡通全景（地标、河海、树、车船），
  按城市当地时间切换白天 / 黄昏 / 夜晚，大本钟指针显示当地时间。全景宽 720 单位，`viewport`
  取西半或东半，让不同页面看到同一座城市的不同角度。卡片较矮时按高度缩放并向两侧多露全景，不裁掉尖顶。
- **原创形象**：空状态与加载使用程序化绘制的“小云”（`PuffCloudBuddy`，会眨眼、浮动），不依赖旧吉祥物素材。

### 组件

| 组件 | 用途 |
| --- | --- |
| `puffPageHeader` | 大标题 + 副标题；圆形搜索按钮长成搜索框；管理收起键盘按钮。保留 `sceneSearch.*` 辅助标识供 UI 测试 |
| `PuffSceneCard` | 上半卡通城市、下半白色说明的明信片 |
| `PuffAvatar` | 糖果色外圈头像，可带在线圆点 |
| `PuffCountBadge` / `PuffTag` / `PuffIconBubble` | 未读数、状态标签、分组图标 |
| `PuffFilterBar` | 横向胶囊筛选，选中态滑动切换 |
| `PuffEmptyState` / `PuffLoadingDots` | 空状态与加载 |
| `PuffCity` | 城市中文名、当地时间与问候语 |

### 性能

城市场景分四层：天空与远景、云鸟星星、地标与地形、摩天轮与车船。只有两层动态层逐帧重绘（30 fps、
异步渲染），页面不可见、App 不在前台或开启减弱动态效果时暂停。静态层只在尺寸或时段变化时重绘。

### 迭代城市画面

场景代码只依赖 SwiftUI，可在 macOS 上用 `ImageRenderer` 批量渲染全部城市与时段做对照，不必构建 App。
新增城市时在 `PuffCityRecipes.swift` 追加配方并在 `PuffCityCatalog.all` 注册。

## 旧设计基础（未迁移页面）

LingoTrip 的其余界面以旅途场景和角色关系为主，UI 提供清晰层级，不用统一卡片覆盖所有页面。

### 原则

- 优先使用 SwiftUI/UIKit 原生导航、Tab、菜单、Sheet、滚动和辅助功能行为。
- 高频反馈短促克制；明显弹跳只用于奖励、确认等低频时刻。
- 页面构图和业务组件留在对应 Feature。
- 多个 Feature 稳定复用的视觉或行为原语再进入 `DesignSystem`。

### DesignSystem 内容

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

## 统一视觉原生实施基准（待审阅）

[2026-10-31 原生设计基准](design/unified-native-2026-10-31/README.md)提供 16 个主要页面的
可编译 SwiftUI 展示源码及真实模拟器截图重现方式，作为后续统一视觉的具体审阅方案。
它尚未迁入正式组件库，也未记录为用户已认可；正式实现复用同一视觉源码和素材，
通过数据适配器连接业务，并使用相同设备、字号和数据进行截图对照。
