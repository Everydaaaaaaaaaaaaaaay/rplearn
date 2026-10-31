# 咕游记统一视觉 · 原生实施基准 v1

2026-10-31。用户随后确认按此方向统一现有界面，并要求适配重构后的活动系统。正式接入与更新后的活动布局见[实施记录](../unified-2026-10-31/implementation.md)。本目录保留初次审阅的独立展示源码与示例数据，不代表当前正式业务结构；赴约业务仍未实现。

## 图与实现的关系

图片直接来自独立 iOS 展示程序 `cn.guyouji.design.unified`：UIKit 启动、SwiftUI 页面、MapKit 地图、系统字体与 SF Symbols。没有调用生图，没有描摹、修图、额外光影或在截图外加设备包装。拼排仅将原图等比缩到 1/3 并在外侧添加页面名，单页 PNG 保持模拟器输出字节。

这份 SwiftUI 源码是后续视觉实施对照基准。接入时迁移相同颜色、字号、组件、间距、素材和布局，通过数据适配器替换本地示例值；不根据图片另做一份近似实现。若需变更视觉，先更新此基准并重新渲染审阅。相同设备、系统、字号与数据下，以截图对照验收；不同屏幕、系统原生控件、键盘、动态文字和实时地图会自然变化。

## 具体范围

16 个主要页面：首页、地图、城市活动、剧情目录、剧情阅读、约定详情、赴约故事、约定总结、信息、聊天、联系人、角色详情、我的、学习、设置、共同记忆。另外保留深色聊天/设置、大字赴约/设置、自定义输入 Sheet 的截图。

- 叙事：延续现有剧情的场景与人物构图，统一纸色阅读卡、细金线及选择按钮。赴约使用城市实拍，增加自由输入入口。
- 场景：保留首页、城市活动及联系人等场景差异，统一导航、信息卡、底部栏；不将整个 App 改成相同背景。
- 功能：聊天、学习、设置使用一致的墨绿、暖纸色及层级。角色、记忆和总结共用关系信息表达。
- 地图：真实在线 MapKit 卫星地图；城市文字通过地图坐标投影定位并随地图更新。底部旅行卡使用相同组件。地图瓦片依赖系统服务，不承诺固定瓦片像素。

## 组件约束

| 项 | 实际源码值 |
| --- | --- |
| 浅色底 / 纸 / 正文 | `#F1F1EA` / `#FAF6EA` / `#25352E` |
| 深色底 / 纸 / 正文 | `#141D19` / `#222D27` / `#F0EFE4` |
| 主操作 | 浅色深绿 `#2C4338`，深色浅绿 `#B6C6AA` |
| 页面边距 | 常规 20pt；阅读卡外侧 18pt |
| 圆角 | 常规 12pt，选择 6pt |
| 点击目标 | 图标通常 44×44pt；主按钮最小高 50pt |
| 字体 | 原生语义字号；少量场景大标题使用系统 serif |
| 按压 | 同一透明度反馈，不添加等待 |

组件实现在 [DesignSystem.swift](DesignSystem.swift)，页面在 [Screens.swift](Screens.swift)，独立入口在 [App.swift](App.swift)。实现时仍遵守 Feature 依赖边界，稳定共享组件进入正式 DesignSystem，页面构图留在 Feature。

## 素材与场景记录

既有场景及角色图直接复制仓库资源，路径和 SHA256 由 `render.py` 写入生成记录。新增赴约照片复用前一版准备包：[照片清单与许可](../appointments-2026-10-31/photos.json)。小威尼斯、樱草山、诺丁山避开已有双层巴士等主体。无源文件改色或修补；裁切、渐变遮罩、纸卡透明度均由真实 SwiftUI 实现。

本版本查看了三张城市照片的实际手机裁切、叙事文字与亮背景的对比、约定时间地点、总结内容层级及自由输入弹层。照片表示城市氛围，界面信息明确说明并不逐帧对应故事发生地。叙事截图选用诺丁山，约定选用樱草山，总结选用小威尼斯；正式赴约轮播沿用之前的独立城市氛围方案，当前展示程序没有实现轮播。

这是一份设计审阅记录，不将照片候选状态升级为正式发布批准。真实功能、所有城市素材、背景轮播动态验收和完整交互仍需施工后按[场景验收规范](../../activity-scene-visual-acceptance.md)验证。G3 视频循环不适用本次静态截图。

## 重现

需要当前 Mac 的 Xcode 与一个已启动的 arm64 iPhone 模拟器。SDK 路径通过 `xcrun` 读取；无需工程生成、账号或后端。

```sh
python3 docs/design/unified-native-2026-10-31/render.py --capture <SIMULATOR_UDID>
python3 docs/design/unified-native-2026-10-31/render.py --skip-build --capture <SIMULATOR_UDID> --pages chat,settings --dark
python3 docs/design/unified-native-2026-10-31/render.py --skip-build --capture <SIMULATOR_UDID> --pages settings,meetup --large
python3 docs/design/unified-native-2026-10-31/render.py --skip-build --capture <SIMULATOR_UDID> --pages meetup --composer
python3 docs/design/unified-native-2026-10-31/package.py
```

最后一步使用本机 Pillow，只负责图片尺寸检查、等比拼排、HTML 原图索引及 SHA256。全部生成物在被 Git 忽略的 `build/unified-native-design/`，源代码和重现说明入库。`index.html` 是原生截图集，不是另一份浏览器设计稿。

## 验证边界

- 实际编译、签名、安装、启动展示程序；检查全部 16 页的标准截图。
- 捕获环境：iPhone 18 Pro、iOS 27.0、SDK 27.1，402×874pt、3×，原图 1206×2622。默认 Dynamic Type `.large`；补充大字 `.xxxLarge`。
- 深色/大字是抽查状态，不表示每页在所有辅助功能和最小屏幕上均已验收。
- 自定义 Sheet 通过与按钮相同的状态自动打开后进行原生截图检查。Computer Use 的 Device Hub 窗口捕获出现系统错误，未将自动打开截图当作手动点击、键盘与拖拽测试通过。
- 本地示例数据和页面跳转用于表达视觉，不连接真实账号、AI、好感度结算、记忆存储、语音或支付。没有对正式 App 运行全量测试。
