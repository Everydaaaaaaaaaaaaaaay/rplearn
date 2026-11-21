# iOS 静态素材无损减容 · 2026-11-20

以 `48de5d58` 的 arm64 Release 安装包为基线。同一 Xcode 和构建配置下逐文件统计安装包字节，范围包含静态素材和仅供开发预览的资源。

| 资源 | 基线 | 本版 |
| --- | ---: | ---: |
| 图库 `Assets.car` | 154.58 MB | 153.24 MB |
| 剧情背景与立绘 | 77.70 MB | 51.14 MB |
| 54 张城市活动照片 | 159.89 MB | 159.89 MB |
| 完整安装包 | 804.25 MB | 771.86 MB |

29 张剧情 PNG 改用无损 WebP。118 张背景和剧情 JPEG 重新编码熵表，保留原扫描方式、尺寸、方向和 ICC。Pillow 与 Apple ImageIO 分别对最终 147 张替换图解码对照，像素均一致，含透明立绘。照片布局、版权和来源沿用[城市背景记录](../../Assets/TabHubScenes/2026-11-16-v1/acceptance-v1.md)与[城市实拍高清验收](../../Assets/Activities/CityPlaces-v2/acceptance-v7.md)。[剧情美术清单](../../Assets/Stories/Departures/production.json)保存当前运行文件及 SHA256。

城市活动原 JPEG 已优化过基线熵表。更紧凑的渐进式试验在 Apple ImageIO 下引入像素差异，因此正式包沿用 54 张已审照片的原始字节。十五城的照片、尺寸、构图参数、署名与哈希通过 `Tools/ContentPipeline/activity-scene-gallery.py` 复验。45 个剧情版本的所有镜头素材引用均可解析。

正式包排除了营销录制头像、学习音频样例、外出样例和单独的照片审查清单等 Debug 文件，产物逐项核对通过。公园、池畔、雨天咖啡馆和相遇过渡视频仍由新手教程或旧活动回退入口使用，四段原视频均在本版正式包内。对应动态证据沿用[旧场景记录](../../Assets/Activities/RealMotion-v5/acceptance-v5.md)和[相遇过渡记录](../../Assets/Activities/EncounterJourney/acceptance-v5.md)。

用剧情阅读器相同的 1280 像素 ImageIO 解码参数，在 Mac 上对每张替换立绘各解码三次。中位耗时由 21 ms 增至 39 ms，95 分位由 30 ms 增至 49 ms。阅读器仍在后台解码并复用当前镜头图片，真机解码耗时待实测。

iPhone 18 Pro 模拟器通过纽约活动正常入口、实景切换及进入外出剧情，也通过伦敦主线原生翻页及两处 Oliver 立绘显示。已查看纽约首屏、伦敦书店门口与手稿镜头截图。结果位于 `build/size-audit/lossless-native.xcresult` 和 `build/size-audit/lossless-art.xcresult`。第一轮纽约剧情测试的预制配音断言超时，测试进入最新 v2，而当前配音库的纽约主线录音属于 v1，v2 会走实时朗读。正式包前后 464 个配音资源逐文件比对一致。架构检查与 Release 构建通过。
