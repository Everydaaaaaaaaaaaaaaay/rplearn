# 活动世界真机验收 v9

2026-11-16，Codex 自检。本次真机抽检范围通过。沿用 [v7](acceptance-v7.md) 的 54 张高清照片、来源许可、原生细节和大小屏裁切证据，以及 [v8](acceptance-v8.md) 的正式世界接入、独处和迁移测试。本轮补齐已解锁真机的页面、交互与照片显示复核。

用户随后反馈真实服务入口读取失败，定位为客户端拦截 `/v2/`。本版普通入口结论适用离线网关，真实请求链路的补充修复与真机复验见 [v10](acceptance-v10.md)。

## 版本与设备

正式世界为 `2026-10-31-places-v1`，15 城、54 地点、200 NPC、800 条初遇路径和 200 段重逢。正式清单哈希为 `8cece8943a75de358dab5fe0bad089b40f50a7faa061425cdee9509045e2807a`。本次生产源基于 `4478e447`，测试隔离修订为 `eb6e2a63`。

设备为 iPhone 13，iOS 27.2，原生截图 1170×2532。本轮使用独立 `build/DerivedData-ActivityAcceptance`。测试启动通过现有 `UI_TEST_WELCOME_CAPTURE` 分支跳过已保存会话恢复，使用内存工作区、独立外出进度 namespace 和离线网关。人物头像为预览占位，照片使用正式入包资源。

## 检查结果

| 范围 | 结果与证据 | 观察范围 |
| --- | --- | --- |
| 内容与照片完整性 | 通过。发布 CLI 与本地 gallery 校验均通过，54 个唯一照片哈希、地点、作者许可和裁切配置匹配 | 本轮复核全部清单和资源，原图地理与空间沿用 v7 |
| 真机照片与全屏入口 | 通过。原生画面确认当地实拍铺满、白字透明描边胶囊、箭头和底部导航可见 | 人工观察纽约高线公园、伦敦南岸、内罗毕博物馆庭院及咖啡馆阅读背景，南岸全图可打开 |
| 大字与阅读布局 | 通过。最大辅助字号的南岸标题、博物馆两行长标题、照片信息、独处中文与结束入口可读 | 照片信息和故事正文可滚动，结尾视口保留结束操作 |
| 普通首页入口 | 通过。纽约当前城市从「城市活动」进入高线公园，箭头切换、返回重进及地点按钮进入故事 | 使用普通页面组件、内存测试资料和离线正式世界网关 |
| 外出状态与足迹 | 通过。实际选择、暂停、进程重启续读、结束和足迹中的选择记录一致 | 咖啡馆样板两次选择路径 |
| 独处 | 通过。统一中文句“你在这里待了一阵，却没有与谁交谈。”、结束按钮与阅读页均可用 | 最大辅助字号 |
| 线上公开人物资料 | 通过。每城抽一人，共 15 人，稳定身份、头像 ID 与完整当前人物卡均匹配正式分配 | 公开旅伴号只读接口，模型调用为零 |

四项真机 XCUITest 全部通过，失败 0、跳过 0。覆盖两项 `CityPlaceOutingTests`，以及 `CitySceneGalleryTests/testHomeActivityEntryUsesCurrentCityPhotographs`、`testLargeTextCreditsOriginalAndFifthPlace`。后者同时检查五地点城市、三地点城市末页、全图和照片信息。

照片为静态实拍。本轮沿用既有手势与呼吸箭头证据，真机定向路径验证箭头切换及末页状态。动态视频、循环接缝和自然步态检查在本版无对应素材。

## 证据与复现

- 真机测试结果为 `build/activity-acceptance-20261116/device.xcresult`，汇总为同目录 `device-summary.json`，日志为 `device-test.log`。
- 导出 17 张原生截图，映射保存在 `build/activity-acceptance-20261116/screenshots/manifest.json`。人工查看了普通纽约入口、南岸大字、博物馆长标题、咖啡馆开场与结尾、独处结尾、足迹、照片信息及全图。
- 最终手机画面为 `build/activity-acceptance-20261116/final-device.png`。通过 Device Hub 的 Screenshot 保存原生截图并观察，确认手机保留在伦敦泰晤士河南岸的完整世界离线活动入口。启动回执为同目录 `final-device-launch.json`。
- 线上 15 城资料抽检结果为 `build/activity-acceptance-20261116/online-public-cards.json`。公网 `/health/ready` 返回 `ready`。
- 模拟器通过 `Scripts/preview.sh preview world-preview` 复用已有 Debug 构建安装，保留完整世界预览。

真机使用 `xcodebuild -project LingoTrip.xcodeproj -scheme LingoTripPerformanceTests -configuration Debug -destination 'platform=iOS,id=<连接的 iPhone UDID>'`，指定上述两个测试类中的四项路径、独立 DerivedData、已有 SourcePackages、签名团队与 `com.tiantian.lingotrip` bundle ID。原生结果与日志保存在本机本次验收目录。

内容与资源复核命令如下。

```sh
(cd Backend && pnpm exec tsx src/cli/activity-world.ts release-check config/activity-world/2026-10-31-places-v1.json ../App/Resources/npc-library-v3.json)
python3 Tools/ContentPipeline/activity-scene-gallery.py
```

## 边界与结论

本轮关闭 v8 的锁屏导致的真机界面待验项，真机抽检范围可交付。全部 54 张照片的原图与资源完整性沿用并复核既有证据，本轮真机人工观图为上述抽样范围。

本轮真实老账号的资料迁移、游客认领与跨设备冲突恢复沿用 [11 月 15 日发布证据](../../../docs/verification/activity-world-release-20261115.json) 中的隔离测试和线上合成账号结果。真实老账号的完整真机端到端迁移、语音音质仍待专项实测。

Xcode 记录两条内部 QoS 等待警告，尚未定位来源。本轮未观察到对应卡死或交互失败，保留警告记录供性能复核。测试后的 devicectl 诊断采集报错，xcresult 汇总为 `Passed`，四项测试及 17 张附件完整。

本轮改动包括两处测试的会话隔离配置与验收文档。上线世界和照片版本沿用正式发布记录。
