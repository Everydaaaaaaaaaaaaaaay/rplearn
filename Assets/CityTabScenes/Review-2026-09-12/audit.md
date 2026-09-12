# 十五城信息 / 联系人背景审查 · v1

2026-09-12，c955。范围为 `messages_<city>_glass` 与 `contacts_<city>_glass` 共30张；不是玄关首页或地图背景。资产哈希见 [before.json](before.json)。以下来自实际随包图片整图检查；最终替换与原生大小屏复验尚未完成，不能作为新版本放行。

## 选择依据

目标是大众熟悉的城市地标/文化符号，不把旅游门票销量榜当作视觉辨识度排名，也不声称存在客观第一、第二名。优先采用旅游机构明确介绍的标志、城市独有轮廓与文化符号；同城两页互补。题材正确但核心轮廓被裁掉、原始细节不足也须修复。

已读取 [Visit London](https://www.visitlondon.com/things-to-do/sightseeing/london-attraction/top-ten-attractions)、[Visit Jamaica 金斯敦](https://www.visitjamaica.com/resort-areas/kingston/)、[Destination Toronto](https://www.destinationtoronto.com/things-to-do/attractions/must-see-attractions/)、[New Orleans 法国区](https://www.neworleans.com/plan/neighborhoods/french-quarter/)、[Visit Manchester](https://www.visitmanchester.com/things-to-see-and-do/attractions/)、[VisitScotland 爱丁堡](https://www.visitscotland.com/places-to-go/edinburgh/things-to-do)、[美国国家公园管理局自由女神](https://www.nps.gov/stli/index.htm)、[肯尼亚野生动物管理局内罗毕国家公园](https://www.kws.go.ke/nairobi-national-park)。部分页面通过浏览器读取，HTTP直取曾被拦截或重定向；未把失败页面当成依据。

## 逐城两张审查

| 城市 | 信息页现状与处理 | 联系人页现状与处理 | 判断依据 / 新候选方向 |
| --- | --- | --- | --- |
| 伦敦 | 塔桥题材通过；来源文件说明为AI生成，需替换真实摄影，并保留双塔轮廓 | 红巴士可辨识，但本轮优先改为大本钟 / 国会大厦，补足最强地标联想 | Visit London列大本钟、国会大厦为iconic sights；[塔桥](https://en.wikipedia.org/wiki/Tower_Bridge)是recognisable London landmark |
| 墨尔本 | Flinders Street站中央穹顶、拱门可辨识，保留题材，复核短屏顶部 | City Circle绿黄电车有代表性，保留题材，复核细节 | [Flinders Street](https://en.wikipedia.org/wiki/Flinders_Street_railway_station)明确为cultural icon及most recognisable landmarks；[电车](https://en.wikipedia.org/wiki/Trams_in_Melbourne) |
| 纽约 | 自由女神题材通过，但火炬贴顶；从原图重新构图 | 时代广场题材与霓虹街谷辨识度通过，拟保留 | NPS自由女神；[时代广场](https://en.wikipedia.org/wiki/Times_Square) |
| 开普敦 | 近距离山壁丢失桌山平顶轮廓，替换为从城市/海岸远眺 | Bo-Kaap彩色街屋可辨识，拟保留 | [桌山](https://en.wikipedia.org/wiki/Table_Mountain)平顶是显著特征；[Bo-Kaap](https://en.wikipedia.org/wiki/Bo-Kaap) |
| 新加坡 | 金沙只剩中间一栋，三塔船顶结构不完整，替换机位 | 鱼尾狮题材通过，右缘被裁，需重做构图 | [金沙](https://en.wikipedia.org/wiki/Marina_Bay_Sands)三塔与SkyPark；[鱼尾狮](https://en.wikipedia.org/wiki/Merlion)为官方吉祥物与城市象征 |
| 都柏林 | 半便士桥题材通过，桥端裁切严重，重做构图 | Merchant's Arch巷道地域正确但直接辨识度弱，优先换Temple Bar红色酒吧立面 | [半便士桥](https://en.wikipedia.org/wiki/Ha%27penny_Bridge)；[Temple Bar](https://en.wikipedia.org/wiki/Temple_Bar,_Dublin)文化区/旅游目的地 |
| 爱丁堡 | 城堡题材通过，但过近竖裁使整体形态难辨，重新选图 | Dean Village漂亮但不是首要城市符号，换皇家一英里与圣吉尔斯 | VisitScotland；[城堡](https://en.wikipedia.org/wiki/Edinburgh_Castle)是城市可识别象征；[皇家一英里](https://en.wikipedia.org/wiki/Royal_Mile)为老城最繁忙旅游街 |
| 温哥华 | 泛化天际线且天空/楼群细节粗糙，替换为Canada Place白帆 | Gastown蒸汽钟完整可辨，拟保留 | [Canada Place](https://en.wikipedia.org/wiki/Canada_Place)的白帆结构；[Gastown](https://en.wikipedia.org/wiki/Gastown)历史街区 |
| 奥克兰 | 天空塔完整可辨，拟保留 | 天空塔与帆船港共同表达City of Sails，拟保留 | [天空塔](https://en.wikipedia.org/wiki/Sky_Tower_(Auckland))明确为iconic landmark；[Westhaven](https://en.wikipedia.org/wiki/Westhaven_Marina) |
| 内罗毕 | 从KICC望出去的普通楼群，不是KICC本体；换圆柱塔地标 | 国家公园长颈鹿与城市同框题材通过，但动物被右侧截断，重做构图 | [KICC](https://en.wikipedia.org/wiki/Kenyatta_International_Convention_Centre)；KWS称内罗毕国家公园为The World's only Wildlife Capital |
| 多伦多 | CN塔完整、夜景辨识度通过，拟保留 | 市政厅/市民广场属于官方iconic景点，保留题材，复核裁切 | Destination Toronto明确推荐CN塔与Nathan Phillips Square的Toronto Sign；[市政厅](https://en.wikipedia.org/wiki/Toronto_City_Hall)为most distinctive landmarks之一 |
| 悉尼 | 歌剧院仅剩画面左侧小部分，替换为贝壳主体完整的机位 | 港湾大桥拱形被横向切断，重新选图/构图 | [港湾大桥](https://en.wikipedia.org/wiki/Sydney_Harbour_Bridge)与[歌剧院](https://en.wikipedia.org/wiki/Sydney_Opera_House)共同构成悉尼标志 |
| 新奥尔良 | Bourbon Street铁艺阳台街景题材通过，复核细节 | 电车被两边截断，优先换Jackson Square / St Louis Cathedral完整轮廓 | 官方法国区介绍称其oldest and most iconic neighborhood，并以Jackson Square、St Louis Cathedral为中心 |
| 曼彻斯特 | Castlefield运河当地真实，但缺少最强城市辨识符号；更换 | 普通运河与现代楼房辨识度偏弱；更换 | 足球场 / United Trinity，与市政厅哥特钟塔互补；[Old Trafford](https://en.wikipedia.org/wiki/Old_Trafford)、[市政厅](https://en.wikipedia.org/wiki/Manchester_Town_Hall)；官方景点页单列Sporting Attractions |
| 金斯敦 | 普通俯瞰城区远景辨识度弱，换Bob Marley Museum或Devon House | Bob Marley雕像与雷鬼文化明确，拟保留 | Visit Jamaica称金斯敦为雷鬼诞生地、Bob Marley Museum为iconic且must-see，并推荐Devon House |

## 共同技术问题

- 28张原资产为固定长屏比例，SE短屏会再次裁掉上下；伦敦两图则相反，宽图在长屏裁两侧。不能只看文件尺寸。
- 不能把横向宽景简单中心裁成窄条：金沙、悉尼、桌山已有明确失败实例。候选须在实际aspect-fill视口下保住主体，无法满足时换机位。
- `photo_credits.txt` 与 `CityScenePhotoCreditsView.swift` 在伦敦、曼彻斯特、爱丁堡、多伦多不一致。最终来源按实际入包资产更新；新图不得继承不相符的作者。
- 信息/联系人资产还被剧情列表复用。资源名保持稳定，最终补查相关缩略图，避免把图片更新误当作仅影响两页。

## 下一版本验收

逐张查看无UI整图与原生细节；用375×667、402×874、440×956等比例检查核心轮廓，再在标准和短屏模拟器截图复查可读性、导航与搜索。保留最终来源/许可、原始尺寸、裁切坐标、SHA-256及每图结论。测试通过不代替看图；未完成或存疑项保持待证实。
