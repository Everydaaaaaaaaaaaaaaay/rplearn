# 十五城实拍影片 v5（2026-09-12）

状态：已交付。完整影片通过用户预览验收，App 解码、标准屏及小屏 UI 测试通过，已通过局域网覆盖安装至用户 iPhone 13。

## 本版解决的问题

- 十五城来源已补齐。金斯敦采用 Spicy_FPV_Jamaica 的 UWI (Mona) gardens and Ruins（YouTube OtiXjWrmNvo），原生 1920×1080 / 60 fps，视频 CC Attribution；选取 15–16 秒的校园遗迹花园，原先车内高速候选不再使用。
- 新奥尔良原片 10 秒附近清晰显示 RTA 2012 号红色电车及 CEMETERIES 线路牌；源页同时有 New Orleans / Louisiana 标注。不是仅凭模糊城市标签判断。
- 伦敦与新奥尔良使用偏心裁切，保留塔桥塔楼、电车主体；其他城市使用中心竖屏裁切。
- 奥克兰保留此前 Piha 的明确地点与 CC 证据，不重新下载、不以新片替换旧证据。
- App 内“影像来源与许可”列出十五城作者、源页面及许可，并说明裁切和无声编码。

## 规格与复现

720×1280，60 fps，900 帧，15.000 秒，单视频轨、无音轨。每城取连续 60 个原片帧，无插帧、复制帧、倒放、慢放或叠化。59.94 原片逐帧映射至 60，沿用用户确认。

逐城源 SHA256、原始 ffprobe、局部帧范围与过滤器：`candidates-v5.json`。`render-v5.py --sources SOURCE_DIRECTORY --output OUTPUT_DIRECTORY` 校验原片哈希后可重建。源大文件保留 build 缓存，不进入 Git。

成片 SHA256：`68b90ecbfc8424445c9a63db848a4839784c32c665c3536dcc32c1d06fec3684`；大小 11,982,426 字节。

| 城市 | 作者 / 来源 | 源帧范围（末帧不含） | 地点依据 |
| --- | --- | --- | --- |
| london | [Anh Nguyen](https://www.pexels.com/video/35286695/) | 120–180 | Tower Bridge |
| melbourne | [Camilo Rodriguez](https://www.pexels.com/video/30331414/) | 120–180 | St Kilda marina and Melbourne skyline |
| newyork | [Emre Yurttakalın](https://www.pexels.com/video/28608250/) | 120–180 | Lower Manhattan / One World Trade Center |
| capetown | [Benjamin Sprankle](https://www.pexels.com/video/29801279/) | 120–180 | Lion’s Head and Cape Town Atlantic coast |
| singapore | [Vasilis Karkalas](https://www.pexels.com/video/37147087/) | 120–180 | Marina Bay Sands and Singapore Flyer |
| dublin | [Flávio Nascimento](https://www.pexels.com/video/29478528/) | 120–180 | Ha’penny Bridge / River Liffey |
| edinburgh | [Mateusz Max Maksiak](https://www.pexels.com/video/38682240/) | 120–180 | Edinburgh Castle |
| vancouver | [The Six](https://www.pexels.com/video/33290794/) | 120–180 | Burrard Bridge / False Creek |
| auckland | [Beautiful New Zealand Scenery](https://www.youtube.com/watch?v=gi_vNfIpXKU) | 300–360 | Piha Beach / Auckland, explicit source title and description |
| nairobi | [Ken Mwaura](https://www.pexels.com/video/29069413/) | 120–180 | Nairobi skyline / source page |
| toronto | [Numan Gilgil](https://www.pexels.com/video/29904667/) | 120–180 | Toronto railway corridor and Lake Ontario |
| sydney | [Ben Prater](https://www.pexels.com/video/36427881/) | 360–420 | Sydney Opera House |
| neworleans | [Ahmed Ari](https://www.pexels.com/video/13107072/) | 600–660 | RTA streetcar 2012, CEMETERIES route sign; source New Orleans tag |
| manchester | [Declan Conor](https://www.pexels.com/video/25839532/) | 120–180 | Deansgate Square / Manchester skyline |
| kingston | [Spicy_FPV_Jamaica](https://www.youtube.com/watch?v=OtiXjWrmNvo) | 900–960 | UWI Mona campus aqueduct ruins; original title UWI (Mona) gardens and Ruins |

## 检查与边界

- 技术：十五段各解码 60 帧、60 个不同帧哈希；合计 900 帧。这个检查不代替连续观看。
- Xcode 托管测试 `ActivityJourneyTests/testBundledJourneyContainsFifteenDecodableSeconds`：通过，检查实际 App 包内清单、全十五城、名称、15 秒、60 fps、无音轨和逐帧 PTS/完整解码。结果包 `20260911T185450Z-24861.xcresult`。
- 已查看全十五城竖屏抽帧，并复查金斯敦/伦敦/新奥尔良片段四个时刻的构图。无合成室内、家具、人物缩放，S1/S2 不适用。
- 连续观感由用户审阅完整 MP4 后确认，详见文末。当前工具给模型的是静态图，不以截图序列冒充连续原速观看。
- 按用户要求在完整实拍影片验收后更新；没有发布静图替代版。

## 原问题状态

V-01：地点/原生帧率/来源缺口已补；影片视觉总体验收仍待完成。
V-02：真实视频上倒计时及实机表现待完成 UI / 真机验证。
V-03：旧 Kingston 车内候选已弃用；新 Mona 镜头仍须连续运动审看后才能关闭。

补充：标准模拟器 `testEncounterAppearance` / `testJourneyKeepsTabsAvailableAndCompletesOffscreen` 两项通过（结果包 `20260911T185608Z-25606.xcresult`）；已查看实际深浅模式影片截图，画面已显示，玻璃数字、文案和城市名可读。iPhone 安装包构建成功。小屏检查进行中，CoreDevice 显示手机 unavailable，尚未尝试覆盖安装。

## 用户影片验收（2026-09-12）

已给出完整原速 MP4，并请求播放两遍检查镜头运动/切换。用户明确回复：“手机解锁了，视频没问题。”本版影片依据用户预览验收放行；不声称 Codex 曾独立连续观看，不将此前静态抽帧升级为动态审看证据。V-01 / V-03 关闭；V-02 的模拟器真实影片可读性已验证，真机安装及用户运行检查范围另记。

## 最终验证与安装

- iPhone SE 3 小屏测试 `testEncounterAppearance` 通过（`20260911T185855Z-26331.xcresult`）。已查看影片截图：数字、文案、城市名与 Tab 均保留可读。已查看结果页布局；内容可滚动。该模拟器命名 Dark 的结果截图实际仍为浅色，因此不声称它补充了小屏暗色覆盖；暗色修复依据标准屏真实暗色截图。
- 已构建签名 iPhone 包，包内电影 SHA256 与源运行资源一致：`68b90ecbfc8424445c9a63db848a4839784c32c665c3536dcc32c1d06fec3684`。
- `devicectl device install app` 通过局域网成功，bundleID `com.tiantian.lingotrip`；安装位置 ID `05DE36E3-A941-47B3-9C9A-2F94F1D7F6F3`。覆盖安装，没有卸载、清库或重置用户账号。
- 安装后自动启动遇到 CoreDevice 连接错误（4000，重试 4016）；安装回执成功，不把远程启动失败误报为安装失败。用户可直接点开 App。未声称完成真机性能采样或真机界面审看。
- V-02：影片在标准屏、小屏均正常显示且文字可读，纯色空屏缺资源问题已关闭；实际手机的长时性能不在本次已测范围内。
