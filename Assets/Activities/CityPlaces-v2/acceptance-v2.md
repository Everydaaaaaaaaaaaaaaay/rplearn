# 十五城静态活动场景 v2 验收记录

2026-11-12，Codex 自检。54 处静态场景进入本机预览，正式世界仍为草稿。真机与用户验收待完成。

## 版本与来源

场景、检索词与精确照片标题见 [catalog.json](catalog.json)，138 条候选及拒收原因见 [candidates.json](candidates.json)。54 张选图的来源页、摄影者、许可、源文件与输出 SHA256、尺寸、确定性处理及逐场景空间观察见 [selected-photos.json](selected-photos.json)。App 运行字节与清单一致，读取时再次核对哈希。

照片经过 EXIF 方向修正、RGB 转换、等比缩小与 JPEG 编码，画面以静态背景显示。全图入口保留照片完整构图，摄影许可页展示作者、来源和许可链接。CC BY-SA 衍生 JPEG 继续沿用逐图来源许可。

沿用 v1 的布卢姆茨伯里咖啡馆、马里波恩书店、樱草山三张原图与空间证据，本版重新检查应用裁切。其余 51 张选图逐张查看原图、原生细节和应用尺寸。前版原图记录见 [v1](../CityPlaces-v1/acceptance-preview-v1.md)。

## 画面与空间

| 范围 | 结果与证据 | 边界 |
| --- | --- | --- |
| G0/G1 地理、参照、站位与动线 | 54 张均核对当地出处与可见空间，逐图记录 `spatialNotes`。排除跨城同名、航拍、历史插图与仅商品特写 | 剧情后续需逐条遵循空间约束 |
| G2 完整实拍与细节 | 54 个唯一图像哈希，无生成式修改。检查行人落脚、楼层、护栏、通行、柜台与物品关系 | 照片表示拍摄时情境，季节及周期性市集须与故事一致 |
| G4/U1 标准屏静态应用 | iPhone 18 Pro、iOS 27.0，遍历 15 城 54 处，2 项测试通过，保留 76 张截图。逐场景检查背景、文字卡、入口及裁切 | 本机 Debug 场景预览 |
| G4/U1 小屏最大辅助字号 | iPhone SE 3、iOS 27.0，1 项测试通过，7 张截图逐项检查文字卡裁切、滚动控制、全图与署名。三处/五处列表末项均可达 | 真机待验证 |
| G3 动态 | 本版采用静态照片，无动态素材 | 旧动态场景的未关闭问题继续保留原记录 |

## 本版修复与复查

- 地理误匹配已排除，包括 Romford 与 Borough Market、Stanley 海堤与 False Creek、英国同名 Devon House、休斯敦 Emancipation Park、圣文森特 Kingstown 港口。候选记录保留拒收理由。
- Borough Market 换用清晰的完整棚内照片。Devon House 的机器元数据缺少作者，直接查原来源页后补为 Op. Deo (English Wikipedia)，许可保持 CC BY-SA 3.0。
- 竖图子视图曾扩大点击和无障碍范围，造成相邻卡误触。补上命中边界，隐藏装饰图的无障碍元素，54 处逐一打开并核对实际加载的地点照片标识。
- 标准字号说明卡曾占据过多照片区域，改为内容固有高度。辅助字号曾溢出卡片，改为 350pt 可滚动视口并裁切边界。最大字号检查覆盖文字、全图、署名、伦敦第五处与内罗毕第三处，以及滚动后的控制按钮。
- 九张横图增加独立左右对齐，包括泰晤士河南岸、圣三一学院庭院与海角区海滨长廊。其余沿用中心构图，完整图可查看。

## 测试证据

- 最终标准屏结果 `build/DerivedData/VerificationResults/20261112T113828Z-88304.xcresult`，2 通过、0 失败，含 54 场景遍历和最大字号路径。截图浏览表位于 `build/ActivityWorldPhotos/gallery-v2-final/sheet-1.jpg` 至 `sheet-5.jpg`，已逐表观察。原生截图仍保存在结果包，重复导出的 PNG 已清理。
- 最终小屏结果 `build/DerivedData/VerificationResults/20261112T115003Z-89522.xcresult`，1 通过、0 失败。原生截图在 `build/ActivityWorldPhotos/gallery-v2-compact-final/`，记录辅助字号卡片边界、第五处与第三处的滚动控件、完整原图与署名弹层。
- 原活动阅读路径在 `20261112T111048Z-83895` 中 2 项通过，小屏原活动最大字号独处路径在 `20261112T112641Z-86095.xcresult` 中通过。前者结果包因磁盘空间清理，摘要保留在 `build/ActivityWorldPhotos/failed-verification-summaries.json`，阅读截图保留在 `gallery-third-shots/`。这些结果用于实际阅读流程回归，场景预览的最终视觉以本版复验为准。
- `python3 Tools/ContentPipeline/activity-scene-gallery.py` 核对 15 城、54 地点、54 个唯一照片、作者许可、空间说明、哈希尺寸、应用清单和裁切配置，通过。
- 世界 schema 与 200 人原始身份基线检查通过。后端既有内容保护测试 7 通过，iOS 架构检查、Python 语法、shell 语法和 diff 检查通过。
- 本次 Computer Use 捕捉 Device Hub 返回 ScreenCaptureKit -3811，改用定向 XCUITest 与模拟器截图复核。真机、VoiceOver 人工使用和人耳音质未验证。

## 交付范围

场景素材、当地空间设计和可切城静态预览已实现。世界草稿 manifest SHA256 为 `6100fc1c56f657971a9f2313039179645adfa59bfe246c4a804024bfb0703e7d`。世界清单仍只有 Alex 一份新人物绑定与完整首次剧情，其余 199 人及全量迁移、相遇内容与正式发布属于后续重构。当前正式活动沿用既有入口。照片选择与上述显示检查属于本轮自检，用户验收待完成。
