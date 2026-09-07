# 城市首页：生成与验收

## 当前状态

2026-09-07：15 城独立底图已接入原生首页。此前大屏/小屏点击与边界测试通过，但用户指出墨尔本、都柏林地图透视不符，**撤销之前对入口共面准确性的笼统通过判定**。数值可逆、可点击、截图可读均不能证明承载面标定正确。下文追加独立的像素叠线复核；不声称二维生成图等同于建筑施工图或真实地图测绘。

## 透视复核补充（2026-09-07）

- 根因：错误地手写了地图四角。墨尔本最终 JPEG 左上角实际约 (602,464)，旧标定的 y 为 275；都柏林实际约 (568,494)，旧 y 为 401。单应矩阵虽计算正确，输入却将斜墙错误地近似为正视平面。
- 全部 15 城重新记录最终随包 JPEG 的画框像素四角，而非未裁切母图坐标。地图与同墙剧情共用修正标定。爱丁堡、新加坡、悉尼去掉不必要的倾斜/收缩；奥克兰纠正顶边方向；其他城市按实物边缘精调。
- 复核范围包括各城驻地、地图、剧情、活动共 60 组入口。另修正墨尔本、爱丁堡、多伦多下门板，温哥华/多伦多门楣，以及奥克兰、开普敦、都柏林、温哥华地面。地面只按可见地砖/木板/地垫的共面线索拟合；不把不规则石缝当成正交矩形。
- 修正透视后重新检查边界：墨尔本地图/剧情整体向内移，奥克兰及温哥华活动略上移，防止恢复投影后发生右缘裁切或短屏底栏遮挡。未修改图标字体、材质、组内间距、渲染器或导航。
- 没有生成、编辑、重新压缩任何背景。像素证据和 SHA-256 记录于 `Assets/HomeScenes/perspective-landmarks.json`。画框在图外的部分仅取可见边缘与画面边界的交点，不臆造图外角点。人工边缘识别约 3 px 容差，不应表述成精确相机标定。

复核工具直接编译生产几何代码，避免另写一套看起来正确但与应用不同的投影：

```sh
swiftc Packages/LingoKit/Sources/HomeFeature/Views/HomeDepartureSceneSupport.swift Packages/LingoKit/Sources/HomeFeature/Views/HomeCityScenes.swift Scripts/home-scene-perspective-audit.swift -o /tmp/home-scene-perspective-audit
/tmp/home-scene-perspective-audit
```

输出 `build/HomePerspectiveAudit/<city>.png`：青线是实际画框及网格，黄线是完整入口区域，品红线是入口局部水平线。先核对青线与照片四边，再检查入口同一高度的收敛方向，最后看原生图标文字；不能只看旋转角，也不能要求透视图里不同高度的水平线在屏幕上完全平行。工具检查资源哈希、像素记录和代码一致；这只是漂移防护，**不能替代人工看图**。

回归新增了斜墙地图、正视地图、奥克兰顶边方向、多伦多局部门板方向断言。原有全部城市四角/热区以及 375×667、393×852、402×874、440×956 安全区测试继续保留。

本轮数值/交互证据：

- `build/HomePerspectiveFinalGeometry.xcresult`：10/10；包含全部城市和四种屏幕尺寸。首次回归拦下的墨尔本右缘、奥克兰短屏越界已修正，未放宽断言。
- `build/HomePerspectiveNative.xcresult`：15/15；逐城真实点击地图与活动并返回，剧情沿用两种门向代表城市点击。逐张复看时发现其中开普敦、悉尼截图捕获到了首帧之前的均匀底色，**这两张截图不通过视觉验收，即使点击测试通过**。
- UI 截图测试增加内容区域像素差异等待，排除状态栏/底栏，拒绝均匀启动底色；不以任意固定延时掩盖竞态。这个检查只防止空白帧，不能自动判断透视、字体是否正确。
- 首轮和复测原始 XCTest 附件保留，复核图表只使用有效截图，不修补/伪造截图。墨尔本、都柏林前后对比位于 `build/HomePerspectiveReview`。
- `build/HomePerspectiveFrameReady.xcresult`：开普敦、悉尼 2/2 复测通过，实际场景截图已复核。15 城有效原生截图索引为 `build/HomePerspectiveReviewedAttachments/manifest.json`（13 张首轮有效帧 + 2 张复测帧）；对应总览和五组三城详图位于 `build/HomePerspectiveReview`。全部地图叠线与 60 组入口检查完成；通过的是当前可见对齐、可读性及交互，不声称能从单张生成图恢复精确真实相机参数。

## 不可跳过的门禁

0. **首先证明这是住处内部。** 必须有墙、顶、地面、完整可关闭的入户门及门框，能区分干燥室内和室外；不能以开放凉亭、敞廊或假设画外有门替代室内玄关。鞋柜、书本、地图要处于受围护的室内。门可以关闭（透过真实窗玻璃看到当地街景），无需为表达出门强行生成大角度开门。
1. 真实参考：每城记录实际建筑/旅游机构或建筑项目的参考；不把生成图当参考，不以文化刻板印象代替地方建筑。
2. 独立文生图：不传参考图、不做图生图。失败稿淘汰，下一稿从完整文字约束生成；不得覆盖来源记录。
3. 结构检查：从像素而不是提示词判定。门扇和门洞属于同一透视，闭合时应覆盖门洞；铰链连接门框，锁舌在相反的自由边，门框锁扣对应；扫掠区域无障碍。中央拉钮确有实物，但不可用来解释错误锁具。双扇门必须交代两扇或明确的固定侧扇。不能以画外猜测补救显著矛盾。
4. 建筑连续性：门楣受支撑；柱脚落地，梁柱相接；栏杆连接实际端柱，不能悬空/封不住区域；门槛、平台、阶梯与人行道连贯，尺寸正常，无意外坠落或封堵。
5. 物件关系：家具腿和地面接触、物品与承载面接触、阴影方向一致；书本/包/雨伞不随意放地；鞋成对、包带闭合连接，材质尺度真实。
6. 地域与画面：实际地方风格有依据；不拼贴不可能同时出现的地标；地图大陆轮廓可信，无虚构交通线；生成地图仅是入口承载物，不声称可用作导航地图。
7. 原生 UI：背景不含 UI。复用 HomeDepartureMetalView、DSHologramMaterial 与原生导航；每张独立测量承载面四角、中心及尺寸；图标文字整体投影，热区同源，不以截图烘焙替代实现。
8. 上机复核：每城截图检查文字可读性、物件遮挡、对齐与点击；短屏/长屏测试安全区和缩放，动态字体可访问列表不回退；城市切换图与标签同时更新，无旧城市残留。
9. 通过记录：逐城记录检查结果、发现的问题、淘汰记录、最终文件与测试证据。存在未解释矛盾的图不得标记通过。发现新问题须撤销原判定。

## 五金核对来源

- [中央固定拉钮：用途是拉门，非自动等同于锁舌把手](https://www.gjohns.co.uk/productpdf/download/file/id/20746/name/Round_Centre_Door_Knob_-_Polished_Chrome.pdf/)
- [From The Anvil 中央拉钮固定结构](https://www.fromtheanvil.co.uk/collections/all-products-except-swatches/products/regency-centre-door-knob?variant=51020088410439)
- [TradCo 门锁与门钮实物](https://www.tradco.com.au/products/1021-2000set-rim-lock-and-milled-edge-knob-passage-set/)

源图路径和完整提示词见 Assets/HomeScenes/generation-manifest.json。该清单保留每次独立生成的提示词、来源路径、拒收原因、最终资产和中心裁切参数；拒收稿不进入 Assets.xcassets。

## 撤销与淘汰记录

- 伦敦第一稿：未能明确验证五金与铰链的关系，淘汰。
- 墨尔本第一稿：原图局部放大后发现不同高度的重复门钮，淘汰；第二稿对侧门框出现铰链状五金，再次淘汰；第三稿开放门廊不符合住处内部场景要求，淘汰。
- 纽约第一稿：门五金组合与完整门扇交代不清，淘汰。第二稿入口留白不足，淘汰；第三稿接入。
- 新加坡第一稿：门扇过窄，另一扇未明确交代，不能验证封闭门洞，淘汰。
- 都柏林第一稿：门内外面、门环、锁具关系不清，淘汰；第二稿对侧门框五金可疑，淘汰。
- 温哥华、奥克兰、内罗毕第一稿：虽参考了实际门廊建筑，但画面不构成围护完整的室内玄关，家具出现的环境不符合本项目叙事要求，全部淘汰。
- 开普敦第一稿：放大重新核对双面门钮、锁舌和远侧铰接边后保留；爱丁堡第一稿门叶裁切妨碍结构验证，淘汰。
- 温哥华第二稿：生成的是未经核实的局部街区图，不符合世界地图承载物要求，淘汰。
- 悉尼第一稿：同侧出现两把不同高度的门把手，淘汰。

上述问题不能通过加强提示词就标记解决，必须复查新输出。局部裁切仅用于放大检查，不回写或修补图像。

## 逐城记录

下列入口均使用 `HomeDepartureMetalView → HomePerspectiveArtwork → DSHologramMaterial` 既有渲染路径。各城四角和中心见 `HomeCityScenes.swift`，视觉和热区共享同一单应矩阵。图标与文本保持原有成组比例和间距，不另造渲染器。

| 城市与真实风格参考 | 可见结构核查 | UI 安排 |
|---|---|---|
| [伦敦](https://www.visitlondon.com/things-to-do/place/6642506-belgravia) | 黑色开门：自由边把手与锁舌、远侧铰接边分开；无旧悬空栅栏；门槛连接人行道，室内鞋凳受墙顶围护。 | 右墙地图/剧情，左前地面活动 |
| [墨尔本](https://www.visitmelbourne.com/Regions/Melbourne/Destinations/Carlton.aspx) | 闭合玻璃门覆盖完整门洞；左铰链右单把手；铁艺蕾丝廊在玻璃外，鞋柜在室内；有轨电车与砖排屋表现当地。 | 右墙地图/剧情，下门板活动 |
| [纽约](https://www.pkimdesigns.com/brooklyn-brownstone) | 完整闭合木框门左铰右锁；外部棕石台阶栏杆连接地面；木柜与鞋在室内，不是公共街道。 | 右墙地图/剧情，左前地面活动 |
| [开普敦](https://www.capetown.travel/neighbourhood/bo-kaap/) | 大角度开启的门扇有近处自由边、对应双面门钮及锁舌，远侧铰接边；透视造成窄投影，不是半扇门；无栅栏。当地彩墙街道与室内有门槛分界。 | 右斜墙地图/剧情，陶砖地面活动 |
| [新加坡](https://www.ura.gov.sg/conservation/find-a-building/conservation-portal/jooch/) | 整扇闭合柚木玻璃门左铰右锁，未留无法封闭的半幅口；室内墙顶、花砖墙裙和鞋柜清楚，店屋立面在玻璃外。 | 右墙地图/剧情，门内地面活动 |
| [都柏林](https://www.buildingsofireland.ie/buildings-search/building/50110227/south-circular-road-dublin-8-dublin) | 红门闭合，左铰链右门锁；顶部扇形气窗及右固定侧窗与门叶区分；无内外双面五金混搭。 | 右斜墙地图/剧情，石地面活动 |
| [爱丁堡](https://www.edinburgh.gov.uk/directory-record/1099433/new-town-conservation-area) | 闭合蓝灰单扇门完整；右铰链左锁；石砌围框支撑，鞋柜、围巾在室内；窗外灰砂岩排屋。 | 左墙地图/剧情，下门板活动 |
| [温哥华](https://www.vancouverheritagefoundation.org/discover-heritage/vancouver-heritage-house-styles-hub/house-styles-by-name-and-era/craftsman-styles-1910-1930/) | 闭合木门覆盖框内，右铰链左锁；雨衣在柜面，鞋在搁板；工匠式木瓦住宅位于玻璃外。 | 左墙地图/剧情，右前地面活动 |
| [奥克兰](https://www.macfiearchitecture.co.nz/) | 闭合淡蓝木门左铰右锁；白木板墙与天花构成室内，蕨类和白色维多利亚廊在玻璃外；柜面包、书受支撑。 | 右墙上方剧情、下方地图，避开柜面包；地面活动 |
| [内罗毕](https://museums.or.ke/karen-blixen/) | 闭合木门右铰左锁；廊柱连接柱脚和屋架且在玻璃外；室内石地、柜面书包和鞋成比例。风格参考内罗毕石屋，不声称复刻具体博物馆。 | 左墙地图/剧情，右前地面活动 |
| [多伦多](https://www.destinationtoronto.com/neighbourhoods/old-town/cabbagetown/) | 完整红木闭门左铰右锁，彩玻璃边框和上亮窗；门外红砖山墙排屋及枫树；鞋柜位于室内。 | 右墙地图/剧情，下门板活动 |
| [悉尼](https://www.sydney.com/destinations/sydney/inner-sydney/paddington) | 闭合深蓝门左铰，右侧只有一把黑色把手；外部铁艺阳台连接建筑；帽子、书在室内柜面，无多余第二把手。 | 右墙上方剧情、下方地图，避开帽子；地面活动 |
| [新奥尔良](https://www.neworleans.com/plan/neighborhoods/french-quarter/architecture/) | 完整双扇门在共同门框内闭合，两侧外缘铰链、中缝一主动锁把；右扇小件是对应锁扣；庭院栏杆、柱子有支撑，家具在门内。 | 左墙地图/剧情，双扇门内地面活动 |
| [曼彻斯特](https://www.visitmanchester.com/ideas-and-inspiration/blog/post/ancoats-a-comprehensive-guide/) | 闭合钢框单扇门左铰右单把手，整扇覆盖门洞；室内砖、灰泥与木地板相接；街对面旧工厂窗，室内柜面雨衣、书及下层鞋。 | 右墙地图/剧情，左前地面活动 |
| [金斯敦](https://www.devonhouseja.com/) | 完整闭合木门右铰左单锁把；玻璃外廊柱和栏杆真实连接；室内顶墙地围护，书帽在凳面、凉鞋在架上。风格借鉴而非声称等同 Devon House。 | 左斜墙地图/剧情，右前瓷砖地面活动 |

## 已执行验证与发现

- Xcode 构建、15 城原生 UI：`build/HomeCitiesUI.xcresult`，15/15 通过；每城地图实际点击并返回；伦敦/爱丁堡额外走完剧情、活动入口。
- 小屏 iPhone SE 原生 UI：`build/HomeCitiesSmallUI.xcresult`，15/15 通过；每城实际点击世界地图、城市活动并返回，伦敦/爱丁堡额外验证剧情。全部截图人工视觉复核；`build/HomeCitiesSmallReview` 保留等比例接触表。Max 尺寸为几何验证，未声称已做 Max 真机测试。
- 几何与随包资源：`build/HomeCitiesGeometryFinal.xcresult`，7/7 通过。对照真实 RegionCatalog 的 15 个 ID；全部图片可解码、尺寸与纵横比正确；每个投影可逆，视觉/热区同源且不越界；SE、标准屏、Max 四档画布计算检查。
- 最终单次 JPEG 95 编码后的资源回归：`build/HomeCitiesFinalResources.xcresult`，7/7 通过；构建成功。
- 第一轮几何检查曾失败：若干斜墙热区横向超界、底部活动热区越过有效下界。已修正坐标，未放宽测试门槛。
- 真正运行 iPhone SE 后发现原有画布使用整屏高度，活动入口被浮动底栏挡住；新增统一的 `HomeDepartureCanvas.placement(in:)`，预留底栏空间，背景、投影和热区同步缩放。不能仅以 `isHittable` 判定未遮挡，所以小屏回归改为每城实际点击活动入口。
- 原生全尺寸截图与接触表位于 `build/HomeCitiesUIAttachments`、`build/HomeCitiesReview`。可用 `swift Scripts/home-scene-contact-sheet.swift <导出截图目录> <输出目录>` 重新整理；该脚本仅排版截图用于 QA，不修改背景资产。
- 生产图共约 7.2 MiB，原图不放大，仅中心裁切到统一纵横比；直接由 PNG 母图一次 JPEG 95 编码，避免重复有损编码。移除了旧伦敦 PNG（约 2.3 MiB），Git 可恢复。失败稿不随包，未改动其他工作树或已有模拟器数据。
- 本轮新建的 iPhone SE 临时 QA 模拟器已在截图和结果导出后删除；原有 8883、c955 等模拟器均保留。原生大屏/小屏截图的几何和内容与最终资源一致；最后一次从母图提高 JPEG 编码质量后另做随包解码回归。
- 画面中的纸质地图是环境物件；真正的城市选择/旅行仍走应用原有世界地图。生成图并非实景摄影原片或可用于实际导航的测绘地图。
- 构建日志仍有此前模块依赖扫描警告；本任务未扩展修改无关依赖、后端、聊天、学习或个人页功能。
- 未执行真实旅行消费、生产写入或在线 AI 调用。城市测试通过 DEBUG 的 `UI_TEST_REGION` 提供显示城市，生产仍使用用户 profile.currentRegionID；主线“下一站”来自剧情进度，故不必与当前驻地同名，不能误改为静态城市名称。
