# 活动首页与我的原生方案预览 v1

2026-11-16，按用户要求制作两页可运行的 SwiftUI 方案，并直接提供模拟器原生 PNG。状态为方案预览，供用户审阅设计。

## 版本与内容

基于 `dc6eb782` 增加 Debug 预览。通过免登录内存工作区和 `UI_TEST_TAB_DESIGN_PREVIEW=1` 进入，实际根 TabView 承载两页。页面使用现有 `DSSceneGlass`、`ActivityPlacePhoto`、`AvatarBadge`、`UserAvatar` 和原生字体。活动首页显示樱草山主图、Oliver 赴约条目、马里波恩书店缩略图与地图入口。我的页显示个人资料、英语旅程、收藏、记忆和账户权益。

本版按伦敦制作，昵称、学习水平、金币、积分提示和明日约定为排版示例。城市活动使用完整世界离线网关，赴约使用现有演示服务，其他入口接入现有页面回调。真实账号的动态资料与约定接入属于后续实装范围。

照片来源与许可沿用 [CityPlaces-v2](../../Assets/Activities/CityPlaces-v2/README.md) 的樱草山、马里波恩书店和 [CityTabScenes v2](../../Assets/CityTabScenes/Review-2026-09-12/acceptance-v2.md) 的伦敦联系人背景。地图入口使用原生 SF Symbol 地球图标。主图及缩略图按界面容器裁切，来源查看入口通过主图右上角及剧情卡长按菜单提供。

## 构建与观察

设备为 iPhone 18 Pro 模拟器，iOS 27.0，402×874pt、1206×2622px，普通系统字号。通过 `Scripts/preview.sh build home` 构建安装，再用 `preview me` 切换。两次启动均设置以下环境变量。

```sh
SIMCTL_CHILD_UI_TEST_WELCOME_CAPTURE=1 \
SIMCTL_CHILD_UI_TEST_TAB_DESIGN_PREVIEW=1 \
LINGOTRIP_SIMULATOR_UDID=659893A7-0822-43F4-8DA1-4A92E9C78814 \
Scripts/preview.sh preview home
```

两张交付截图由 `xcrun simctl io <UDID> screenshot <path>` 直接保存，交付文件与捕获字节一致。Computer Use 已查看两张完整 PNG。实际系统状态栏、玻璃材质、阴影、照片与底部 Tab 均保留在截图中。

第一轮活动页标题侵入状态栏，定位为原有场景导航容器忽略根安全区。为容器增加可配置的根安全区选项，本版预览遵循安全区，最终重新构建并确认标题位于状态栏下方。保留首轮捕获为本机迭代证据，交付采用下表的最终截图。

| 页面 | 最终截图 | SHA256 |
| --- | --- | --- |
| 活动首页 | `build/tab-hub-design-20261116/activity.png` | `86aab429cc5a43e7a72511501774b5eb65e976eb1bd9988d823f20bfd3a5d4eb` |
| 我的 | `build/tab-hub-design-20261116/me.png` | `f08ad23fd488aa17fd05b07fe0cc02bd97df4a5dffb18b63bf50905088a9d230` |

构建日志为 `build/tab-hub-design-20261116/build-v2.log`，我的页启动回执为同目录 `me-launch.log`。构建、`Scripts/check-architecture.sh --ios` 与 `git diff --check` 通过。两页首屏文字、卡片和 Tab 均完整显示，地图图标与摄影正常渲染。模拟器保留我的页，可通过底部活动 Tab 查看另一页。

## 范围

本轮交付两页原生设计预览。检查范围为上述标准屏和普通字号的构建与视觉排版。交互路径、大小屏与辅助字号完整回归、深色模式及真实账号端到端接入尚待实装验证。
