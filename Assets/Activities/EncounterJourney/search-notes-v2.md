# 两城扩展搜寻 / 2026-09-10

本轮由 Pexels/Pixabay 扩大到 YouTube，使用“知识共享”过滤，再逐片检查展开说明中的视频许可字段和下载流；配乐授权不充当视频授权。

## 新来源

| 城市 | 来源 | 实测原样本 | 地点证据与选片结论 |
| --- | --- | --- | --- |
| 奥克兰 | [Piha 海滩](https://www.youtube.com/watch?v=gi_vNfIpXKU)，Beautiful New Zealand Scenery | 3840×2160，约 59.94006 fps | 标题和说明明确 Piha / Auckland；说明引用 piha.co.nz。抽帧见黑沙、草坡和海浪；优先候选，运动及竖屏裁切待审 |
| 金斯敦 | [Barbican Road 至机场](https://www.youtube.com/watch?v=B8Fo1ZQz8ec)，Driving Time | 3840×2160，60 fps | 标题明确 Kingston, Jamaica 及路线；24 分附近为沿海道路，车头/车辆明显；仅技术备选，缓速审美未通过 |

两片真实许可字段均允许 CC Attribution 再利用。署名见 previews-v2/CREDITS.md，技术证据见 candidates-v3.json。格式 315 为原质量 VP9 流。
奥克兰请求原片 00:15–00:30，下载样本 18.001 秒；金斯敦请求 24:00–24:08，样本 7.999 秒。流复制可能带关键帧前卷，因此局部帧号不等同于请求起点加时间；选段以清单中的下载文件哈希和局部帧号为准。
预览各取连续 60 帧，输出 1 秒 / 60 fps；60 个解码帧哈希均不同，此检查不能代替原速运动审看。预览为横屏 720p，最终素材仍应从 4K 原片裁切。

## 扩展范围与排除依据

- Pixabay 奥克兰：28776、28372、28764、28371 为 25 fps；28765 为 29.97；134576 为 50。均不足。
- Pexels Piha 搜索中的 32258394 实为 Oregon；关键词命中不能证明地点，排除。
- Kingston 航拍/自然景观：Joeka 12BhNaqKtPg、fo-OT1OBeIs、Cy_9Yf7pbPk 为 24 fps；TimothyM ue8Za0EYGoM 为 30；STOFFinJA EC0nEQ99QNU 为 24；HencepStudios ppmVNkdvL8c 为 24。
- Kingston 街区/旅行：fYOop5xpmHo、NM8z1lZGi9w、EXrIIg9DTk0 为 30；Hle_O8FqlO8 为 50；PaisYsGs8LE 为 25。
- Hope Gardens：wDM7CViH9Is、Y3_-SP11JQ0、kPcJbeDGBKg 均为 30 fps。
- 其他 4K60 CC 候选：Driving Time Uj4rTEQ4QCM 为城市车行，P-AbmWV49TU 为红灯前停车，车辆/仪表台突出；Drone View Jamaica JXJHMndE-5s 开头有大片烧录字幕，路线随后离开 Kingston，不能把全片任意片段标为金斯敦。均未采用。

## 尚未解决

金斯敦仍需更温和、少车辆干扰的最终镜头。两城来源缺口已有技术候选，但十五城整片、运镜速度匹配、手机裁切和玻璃数字仍未验收；旧 New Orleans 13107072 地点证据仍待补足。没有安装运行影片。

## 2026-09-12 补充排除与发布约束

用户明确要求完成十五城实拍影片后才更新，不采用城市静图替代，也不单独安装主题修复。
新增检索：RwHZKLAQlCY（Kingston Waterfront // Sunset // 60fps）提供 720p60，但元数据未提供可复用许可，未采用；s9hmCAuEocw 虽为 CC，说明明确是纽约州 Kingston 且仅 25 fps，排除；DP_6sybRbqY 为 CC、最高 30 fps，排除；CbyBYN7GAgA 不可访问。没有新增放行素材，V-01/02/03 保持开放。

相遇界面已改用 DesignSystem 自适应背景/文字及固定深色主按钮。UI 测试通过（1 项，涵盖深浅两种系统外观），结果包：`/tmp/lingotrip-grammar-derived-20260911/VerificationResults/20260911T184210Z-22502.xcresult`。已查看剧情截图，深浅背景和正文正确切换；此结果不代表正式影片验收或真机安装。测试使用 XCUIDevice.appearance，原 AppleInterfaceStyle 启动参数没有实际切换外观，已替换，结束恢复原外观。
