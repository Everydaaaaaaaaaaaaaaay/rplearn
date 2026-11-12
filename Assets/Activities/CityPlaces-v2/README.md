# 十五城静态活动场景 v2

2026-11-12，15 座城市共 54 个地点，每城 3–5 个。每个地点配一张对应当地的真实照片与独立空间说明。App 使用静态实拍背景，提供全图和摄影许可查看。

## 场景清单

| 城市 | 数量 | 地点 |
| --- | --- | --- |
| 伦敦 | 5 | 泰晤士河南岸、布卢姆茨伯里咖啡馆、博罗市场、马里波恩书店、樱草山草坡 |
| 纽约 | 5 | 高线公园、中央车站大厅、联合广场农夫市集、康尼岛海边栈桥、华盛顿广场 |
| 新加坡 | 4 | 中峇鲁熟食中心、如切彩色店屋街、植物园天鹅湖畔、滨海湾步道 |
| 悉尼 | 4 | 邦迪海岸、环形码头、格里布周末市集、纽镇独立书店 |
| 墨尔本 | 4 | 菲茨罗伊街边露台、霍西尔涂鸦巷、维多利亚女王市场、维州图书馆阅览室 |
| 多伦多 | 4 | 肯辛顿街区、多伦多群岛湖岸、圣劳伦斯市场、酿酒厂历史街区 |
| 温哥华 | 4 | 煤气镇钟楼街口、福溪海堤、格兰维尔岛公共市场、斯坦利公园林径 |
| 爱丁堡 | 3 | 迪恩村河边、皇家英里街巷、卡尔顿山 |
| 都柏林 | 3 | 圣三一学院庭院、大运河岸、乔治街拱廊市场 |
| 奥克兰 | 3 | 伊甸山观景步道、温亚德码头街区、奥塔拉周六市集 |
| 开普敦 | 3 | 波卡普彩屋街、海角区海滨长廊、绿市广场 |
| 曼彻斯特 | 3 | 阿弗莱克斯商店街口、卡斯尔菲尔德运河、曼彻斯特中央图书馆 |
| 新奥尔良 | 3 | 杰克逊广场、法国人街、法国市场 |
| 内罗毕 | 3 | 内罗毕国家博物馆庭院、卡鲁拉森林步道、内罗毕城市市场街口 |
| 金斯敦 | 3 | 德文大宅庭院、解放公园、金斯敦海滨广场 |

## 内容、来源与许可

- [catalog.json](catalog.json) 保存地点名称、背景描述、搜索词、精确来源标题及手机裁切对齐。
- [selected-photos.json](selected-photos.json) 保存 54 张选图的具体来源、摄影者、许可链接、获取文件与输出 SHA256、尺寸、处理记录和逐地点空间观察。
- [candidates.json](candidates.json) 保留 55 处研究对象的 138 条候选记录，包含替换掉的芒特普莱森特方案和误匹配的拒收原因。照片清单中的作者说明、拍摄地点与画面共同用于地理核对。
- App 中的「摄影与许可」展示作者、许可及原始来源页，并说明尺寸缩放、JPEG 转码和显示裁切。CC BY-SA 照片的衍生 JPEG 沿用其来源许可，逐图对应关系见选图清单。
- 整图采用确定性 EXIF 方向修正、RGB 转换、等比缩小及 JPEG 编码。裁切仅发生在界面显示，完整图仍可打开。

本轮补查发现同名跨国地点、邻近但不同的市场、历史插图、商品特写和航拍误匹配，已在候选中记录处置。伦敦博罗市场选用了完整的 2024 年棚内照片。金斯敦的 Devon House、Emancipation Park 和海滨座位均分别核对了牙买加出处。

地方参照包括伦敦南岸的 Queen’s Walk、植物园天鹅湖、卡鲁拉步道和曼彻斯特独立商店入口。每张实际入包照片的直接来源页另在选图清单与 App 中展示。[South Bank London](https://southbank.london/see-and-do/queens-walk)、[Singapore Botanic Gardens](https://sbg.nparks.gov.sg/visit/self-guided-walks/)、[Friends of Karura](https://friendsofkarura.org/forest-maps/)、[Visit Manchester](https://www.visitmanchester.com/ideas-and-inspiration/blog/post/a-guide-to-exploring-afflecks-for-first-time-visitors-and-locals-alike/)

## 剧情使用

`spatialNotes` 明确了照片中的实际动线、楼层、私人区域、季节和时段。图书馆上层书廊、河岸两侧、住户门阶与市场柜台各有对应说明。人物可因工作、候人、通行、义务、偶然停留等原因到场，其当下社交意愿仍由人物与剧情决定。

世界草稿已引用这 54 处地点、同一批照片及空间说明。200 份原始人物资料基线与 Alex 的咖啡馆绑定保留，完整首遇剧情仍在后续重构范围内。新世界当前保持草稿状态。

## 获取与校验

从仓库根运行，照片检索默认使用本版清单，单线程全局间隔至少五秒，429 继续遵循 Retry-After 冷却。已知标题直接查询 imageinfo，遇到小原图时获取标准 960px 缩略图。

```sh
python3 Tools/ContentPipeline/activity-place-photos.py --city london
python3 Tools/ContentPipeline/activity-scene-gallery.py --build
python3 Tools/ContentPipeline/activity-scene-gallery.py
```

后两条命令从已审选图生成或检查本地预览包，核对十五城覆盖、每城 3–5 处、54 个唯一图像哈希、作者许可、逐场景空间记录、JPEG 字节与尺寸、App 清单、裁切配置及陈旧文件。已入包的图片可直接复验。重新获取来源使用候选清单中的精确地址。

本轮运行素材位于 `App/Resources/ActivityPlacesGallery/`，清单为 `city-scene-gallery.json`，横图对齐为 `activity-photo-framing.json`。图片 SHA256 在 App 读取时再次校验。正式世界发布检查独立执行。

## App 预览

```sh
LINGOTRIP_SIMULATOR_UDID=659893A7-0822-43F4-8DA1-4A92E9C78814 Scripts/preview.sh build scenes-preview
```

打开后点左上角城市名切换十五城，再点场景查看背景、全图与署名。此入口使用免登录 Debug 工作区。版本验收、测试证据和待验证范围见 [acceptance-v2.md](acceptance-v2.md)。
