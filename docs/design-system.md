# 设计基础

## 蓬蓬（Puff）设计系统 · 2026-11-21 起

面向儿童与青少年、成人也适用的新设计系统，2026-11-22 起覆盖全部页面：四个 Tab、聊天及其设置与通话、
角色资料与学习、剧情目录与阅读、世界地图、票根与飞行抵达、赴约、城市活动、设置、收藏夹、会员订阅、账号与安全、
欢迎与首次使用、水平测评和登录。源码在 `Packages/LingoKit/Sources/DesignSystem/Puff/`。

旧的 `DS*` 颜色令牌现在只是蓬蓬配色的别名，`DSActionButtonStyle`、`dsSurface`、工作台面板等旧组件也已改为
蓬蓬实现并保留接口；新代码直接使用 `Puff` / `PuffCandy` 与蓬蓬组件。系统 `Form`/`List` 页用 `puffFormStyle()`。
实时通话与晋升仪式保留沉浸式深色，底色取蓬蓬夜空蓝；剧情阅读页保留各章专属插画，只换控件。

### 原则

- **少说明**：界面只放标题、状态、数字和必要的错误提示，不加解释功能或规则的副文案；
  需要的补充信息放进 VoiceOver 标签。
- **白色为主基调**：页面纯白，深色模式为柔和夜空蓝 `#161A2E`，不用纯黑。
- **糖果色只做点缀**：`PuffCandy` 六色（sky、bubblegum、sunny、mint、grape、tangerine），每色含
  `base` 填充、`deep` 白底上的图标与强调字、`wash` 浅底、`lip` 实心按钮唇边。正文始终用 `Puff.Palette.ink`。
  同一位朋友的颜色由名字稳定决定（`PuffCandy.stable(for:)`）。
- **圆润**：全部使用圆体 `Font.puff(_:_:)`，跟随动态字体；圆角 12 / 18 / 24 / 30。
- **字重偏轻**：圆体本身显粗，字重统一取 `Puff.Weight`——页面大标题 bold，卡片标题与名字 semibold，
  按钮与强调 semibold，标签与辅助文字 medium，正文 regular，图标 semibold。不直接写 heavy / black。
- **厚卡片**：白色正面 + 细描边 + 底部 4pt 唇边（`puffCard`、`PuffCardButtonStyle`），按下时正面陷进唇边，
  松手轻弹回来。小按钮用 `PuffSquishButtonStyle`，分组内的行用 `PuffRowButtonStyle`。
- **灵动但可打断**：`Puff.Motion` 全部是弹簧。首屏用 `puffEntrance(index:isShown:)` 逐行错峰弹入，只播放一次；
  角标、星星用 `.puffPop`；展开内容用 `.puffDrop`。“减弱动态效果”时统一降级为短淡入淡出，逐帧动画暂停。
- **点击手感**：四种按压样式外层都是原生按钮（手势、滚动取消、无障碍不变），自带软触感。滚动区里的快速轻点，
  系统要等抬手才显示按下效果，所以轻点后按下的样子停留 `Puff.Motion.tapHold`（0.12 秒）：厚卡片、糖果按钮、
  分组行停留后再触发动作，下压与回弹在页面切走前看得见；小按钮动作立即执行，只延长按下的样子。
  VoiceOver 或减弱动态效果时立即触发。厚卡片按下陷进唇边并缩到 97%；糖果按钮压扁、松手按 `Puff.Motion.jelly`
  晃两下；小按钮松手时 SF Symbol 蹦一下（动作自己给触感时传 `PuffSquishButtonStyle(haptic: false)`）。
  未读角标数字变多时蹦一下。菜单（`Menu`）不套蓬蓬按钮样式，保持系统弹出行为。
- **过渡**：标签切换在淡入的同时让新页面从下方 14pt 轻轻升起、弹簧回位；卡片进入详情用 iOS 18 缩放转场
  （`puffZoomSource(id:in:)` 标记起点，目标页 `.navigationTransition(.zoom(...))`，活动页导航栈通过
  `puffZoomNamespace` 环境值共享命名空间）。聊天、设置这类工作页保持标准推入，避免下拉关闭和滚动冲突；
  推入页的主栈用 `PuffStaggeredStack` 代替 `VStack`，推入的同时各块内容错峰浮现，只在首次出现时播放。
  打开会话后新产生的消息用 `puffArrival(isNew:anchor:)` 从发送方一侧弹出，历史消息原样显示。
- **子页面顶栏**：蓬蓬根页隐藏系统导航栏。新的子页面优先用 `puffPageHeader(title:showsBack: true)`
  把页头和返回按钮画在页面里（普通推入另加 `dsInteractivePopGesture()`），转场两端都不切换导航栏显隐。
  仍用系统导航栏、又从隐藏系统栏的页面缩放进入的子页面，必须加 `dsKeepsNavigationBarVisible()`：
  缩放转场的交互返回会把导航栏淡到透明，取消后不会恢复，顶栏和返回按钮会一起消失。
  回归用例见 `NavigationBarRecoveryTests`、`HomeNavigationTests`。
- **小惊喜**：城市明信片可开 `tapBurst`，点画面迸出糖果色星星和爱心（`puffTapBurst()`，不拦截原有点击）；
  空状态等独立展示位置的咕咕、嘎嘎可开 `reactsToTap`，点一下蹲下、起跳、落地压扁并换个开心姿势。
  按钮内部的吉祥物和画面不开，避免和导航抢手势。
- **页面氛围**：白底页面用 `puffPageTint(_:cameo:)` 设色调，页面底色换成 `PuffPageBackdrop()`：顶部糖果色天空带
  （页头里飘卡通云）渐变回白底，白底铺很淡的旅行涂鸦；页头右侧空着时可让吉祥物坐在标题旁（`PuffPageCameo`），
  其他空白处用 `PuffMascotCameo`。信息天蓝、联系人泡泡糖、活动薄荷、我的葡萄紫，子页面沿用所属标签颜色，
  学习页用旅伴的颜色，登录与测评天蓝。聊天、剧情阅读、答题、赴约阅读等专注页面保持纯白或场景背景。
  正文与卡片始终白底；减弱动态效果时云停住，降低透明度时不画涂鸦。
- **卡通代替实拍**：`PuffCityScene` 用 Canvas 程序化绘制 15 座城市的卡通全景（地标、河海、树、车船），
  按城市当地时间切换白天 / 黄昏 / 夜晚，大本钟指针显示当地时间。全景宽 720 单位，`viewport`
  取西、中、东段，让不同页面看到同一座城市的不同角度。卡片较矮时按高度缩放并向两侧多露全景，不裁掉尖顶。
  由远到近分层：三段渐变天空与日月光晕 → 带受光面的云 → 远景与地平线薄雾 → 水面与地标倒影（涟漪着色器
  `puffRipple` 左右轻晃）→ 投下柔和影子的远岸地标 → 船（带尾迹）、摩天轮、钟针 → 近岸与带暗面的树 → 路上的车，
  最上面在太阳一侧罩一层暖光。船和车分两趟画（`moverPass`），船不会盖到近岸的树和电话亭上。
- **城市活动地点（出去走走）**：十五城 54 个地点用风格化实拍做“活照片”（`PuffPlacePhotoScene`）。
  `Tools/ContentPipeline/stylize-place-scenes.py` 对实拍做语义分割（SegFormer）与单目深度（DPT）分析，
  确定性地裁成竖版、统一曝光白平衡、保边平滑、少量色阶归并、插画调色、细描线和空气透视，并把天空抠空；
  另出一张动态遮罩（R 树叶、G 水面、B 远近）。App 里背后是按当地时间变化的手绘天空和柔边云，
  着色器 `puffLivingPhoto` 让树叶随风轻摇、水面起波并零星泛起柔和波光，镜头缓慢漂移带出远近视差
  （着色器以 600 秒为一圈无缝循环，漂移与云用连续时间）；黄昏偏暖，夜里室外偏蓝变暗、室内只略压暗；
  室内场景飘着微尘。地点浏览页右上角菜单有“照片信息”（摄影、许可与来源）；底部是单行薄卡片
  （地点名与页码点在左、“去逛逛”在右，长名字在左栏内换行，继续外出或无障碍大字号时上下排列），
  顶栏后垫一层与页面底色一致的淡渐变，压住室内照片顶部细碎的天花板。
  验收见 `Assets/Activities/StylizedPlaces-v1/acceptance-v1.md`。
  没有风格化实拍的地点（如赴约地点）仍按地点类型画卡通场景：远处是城市卡通天际线，近处是地点本身；
  赴约阅读页按约定标题和地点名判断场景类型，约定页顶部是城市卡通街景。
- **地图**：世界地图使用柔和的标准地图样式（不用卫星实景），城市图钉是以地标为中心的卡通小图
  （`PuffCitySnapshot.icon`）。
- **吉祥物咕咕与嘎嘎**：`PuffMascot` 显示两只小鸟的三维渲染图，形象沿用改版前定稿
  （`Assets/Brand/Mascots/duo-calibration-v1/corrected.png` 与 `ui-pack-v1`）。咕咕天蓝色、头顶一撮卷毛、
  奶油色心形脸和肚皮、翅膀带浅色斑点、棕色小脚，负责打招呼、指路、庆祝、休息；嘎嘎淡紫色、头顶三片叶形羽毛、
  眼睛以下是带碎绒边的奶油色脸颊、外眼角睫毛上翘、橙色小脚，负责讲解、提醒、鼓励、认可。
  10 种姿态（微笑、挥手、指路、庆祝、打盹、好奇、思考、得意、鼓脸、捧星星）各一张图，睁眼姿态另有闭眼图用来眨眼；
  挥手、庆祝的翅膀单独渲染，按肩膀转轴摆动。呼吸、跳跃、彩纸和 z 等小装饰在 SwiftUI 里叠加，减弱动态效果时静止。
  模型和渲染在 `Tools/ArtPipeline/Blender/mascot3d.py`（Blender，Cycles，透明底，脚底在图高 93% 处），
  `mascot3d-assets.py` 缩到 432px 写入 `DesignSystem/Resources/Mascot3D.xcassets`。改形象后重渲染全部姿态，
  再用 `Scripts/preview.sh build mascots-preview` 一屏检查全部姿态和小尺寸。
  `BrandMascotView` 仍是全 App 的统一入口，八个品牌姿态映射到 `PuffMascot`；空状态通过 `PuffEmptyState(bird:pose:)` 使用。

### 组件

| 组件 | 用途 |
| --- | --- |
| `puffPageHeader` | 大标题 + 副标题；可选搜索（圆形按钮长成搜索框，保留 `sceneSearch.*` 辅助标识）或右侧圆形操作 |
| `PuffSceneCard` | 上半卡通城市、下半白色说明的明信片 |
| `PuffAvatar` | 糖果色外圈头像，可带在线圆点 |
| `PuffCountBadge` / `PuffTag` / `PuffIconBubble` | 未读数、状态标签、分组图标 |
| `PuffFilterBar` | 横向胶囊筛选，选中态滑动切换 |
| `PuffMascot` | 咕咕、嘎嘎吉祥物，可选点击反应 |
| `puffArrival` / `puffTapBurst` / `puffZoomSource` | 新内容弹出、点击迸发、缩放转场起点 |
| `PuffEmptyState` / `PuffLoadingDots` | 空状态（配吉祥物）与加载 |
| `puffFormStyle()` / `PuffBubbleLabelStyle` | 系统 `Form`/`List` 页的蓬蓬外观：浅云底、圆体、图标放进糖果色气泡，保留系统表单行为 |
| `PuffStaggeredStack` | 推入页主栈，内容错峰浮现 |
| `PuffCity` | 城市中文名、当地时间与问候语 |

### 性能

城市场景分四层：天空与远景、云鸟星星、地标与地形、摩天轮与车船。只有两层动态层逐帧重绘（30 fps、
异步渲染），页面不可见、App 不在前台或开启减弱动态效果时暂停。静态层只在尺寸或时段变化时重绘。

### 迭代城市画面

场景代码只依赖 SwiftUI，可在 macOS 上用 `ImageRenderer` 批量渲染全部城市与时段做对照，不必构建 App。
新增城市时在 `PuffCityRecipes.swift` 追加配方并在 `PuffCityCatalog.all` 注册。

## 旧设计基础（历史，令牌已映射到蓬蓬）

以下为迁移前的设计约定，保留供理解旧代码；视觉以上方蓬蓬为准。

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

## 历史方案

[2026-10-31 统一视觉原生基准](design/unified-native-2026-10-31/README.md)已撤回，由蓬蓬设计系统取代，仅作历史参考，
新页面不要依据它实现。
