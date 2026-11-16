# 活动首页与我的页摄影 v1

15 城各两张独立当地摄影，共 30 张。资源用于正式 HomeView 与 MyPageView，随账号当前城市更新。活动地点卡片另沿用已验收的地点照片。

## 文件

- `catalog.json` 保存城市、页面用途、检索词与精确来源标题。
- `candidates.json` 保存检索结果、来源元数据、下载及候选摘要和人工拒收原因。
- `selected-photos.json` 保存实际入包的 30 张照片、作者、许可、城市依据、裁切、原始与成品摘要。
- `reuse-resolution-audit.json` 保存与既有摄影清单的交叉检查结果。
- `acceptance-v1.md` 保存此版原生验收范围与证据。

成品位于 `App/Assets.xcassets/{activities|profile}_{city}_glass.imageset`，来源元数据位于 `App/Resources/hub-scene-photos.json`。活动页右上角可查看当前城市两张背景的来源与许可，设置中的城市背景照片页可查看全部条目。各衍生照片沿用来源的 CC BY、CC BY-SA 或 CC0 许可，署名以清单为准。

处理采用 EXIF 转向、RGB、原生 9:16 裁切、仅等比缩小至最多 1620×2880，以及 JPEG 94 / 4:4:4 编码。新加坡我的页向右裁切以保留塔身。

## 复现与校验

```sh
python3 Tools/ContentPipeline/activity-place-photos.py \
  --catalog Assets/TabHubScenes/2026-11-16-v1/catalog.json \
  --evidence Assets/TabHubScenes/2026-11-16-v1 --candidate-limit 3
python3 Tools/ContentPipeline/tab-hub-photos.py --build
python3 Tools/ContentPipeline/tab-hub-photos.py
```

已选原始下载缓存保留在清单的 `localSource`。最终目录的 `photoTitles` 固定为已选原图，历史精确检索标题保存在 `researchPhotoTitles`，重新运行采图命令可获取已选源文件。被拒收候选只保留来源记录及审看证据，不进入 App。逐次检索保持单线程和服务端限流退避。

## 入包取景

| 城市 | 活动首页 | 我的页 |
| --- | --- | --- |
| 伦敦 | 摄政街弧形街区 | 圣詹姆斯公园 |
| 纽约 | 熨斗大厦 | 中央公园弓桥 |
| 墨尔本 | 皇家展览馆 | 雅拉河畔 |
| 开普敦 | 梅森堡彩色海滩屋 | 克斯滕博什植物园 |
| 新加坡 | 星耀樟宜雨漩涡 | 裕华园 |
| 都柏林 | 塞缪尔·贝克特桥 | 圣斯蒂芬绿地 |
| 爱丁堡 | 维多利亚街 | 因弗利斯公园 |
| 温哥华 | 科学世界滨水 | 伊丽莎白女王公园 |
| 奥克兰 | 奥克兰战争纪念博物馆 | 独树山 |
| 内罗毕 | 肯尼亚国家档案馆 | 乌胡鲁公园 |
| 多伦多 | 皇家安大略博物馆 | 亨伯湾拱桥 |
| 悉尼 | 维多利亚女王大厦 | 悉尼皇家植物园 |
| 新奥尔良 | 花园区布里格斯—斯托布宅邸 | 城市公园朗格勒斯桥 |
| 曼彻斯特 | 曼彻斯特座堂门廊 | 惠特沃思公园 |
| 金斯敦 | 罗亚尔港查尔斯堡 | 罗亚尔港查尔斯堡庭院 |
