# 统一视觉接入正式 App：2026-10-31

范围已由用户确认：本轮只统一现有界面，并适配重构后的城市地点活动；赴约生成、好感度结算和记忆业务不在本轮实现。

## 活动结构复核后的调整

以当前 `CityPlacesView` / `CityOutingView` 和[活动重构进度](../../activity-system-rebuild-progress-2026-10-31.md)为准。此前设计稿的“公园／池畔／雨天咖啡馆＋动作入口”不再作为新版活动实施基准。

- 地点页：同城真实地点照片卡纵向排列，保留当地名称、逐图署名、足迹及继续外出的入口。照片跟随具体地点，不能套用赴约任意同城氛围照片轮播规则。
- 外出页：当前地点照片铺底，标题及朗读／翻译操作放在上方，连续正文、回顾过的选择和当前决策放在下方暖纸阅读区域。普通字号上限为可用高度的 64%，辅助字号为 83%，区域内可原生滚动。
- 固定初见、重逢、独处、选择 ID、确认开场、离线队列、幂等恢复、冲突提示、加好友和提前结束继续沿用原模型；没有改写故事或跳过同步门槛。
- 普通返回仍暂停，重新进入仍恢复同一次外出。阅读时收起主导航，回到地点页后恢复；地点列表仍可切换主标签。

正式内容发布仍由既有 `activity-world-release.json` 和服务端激活状态决定。本轮没有发布草稿人物或照片、导入活动世界或绕过现有门槛。新版界面可通过 `places-preview` 隔离预览，待内容正常发布后正式路径自动使用同一实现。

## 共享设计与页面接入

[原生设计稿 v1](../unified-native-2026-10-31/README.md)的暖纸、墨绿、金线、系统字体、12pt 常规圆角、20pt 边距与 50pt 主按钮进入正式 `DesignSystem`，集中在 `DSReadingPalette`、`DSPaper`、`DSReadingChoice`、`DSReadingRow` 和 `DSBottomBar`。

- 信息与联系人保留各自城市照片和既有排序／侧滑／特别关心／旅伴号搜索，改为一致纸面分组和可见搜索框；收起键盘保留搜索内容。
- 聊天保留语音、翻译、查词、教练点评和消息状态，统一底色、气泡和输入栏。发出气泡与主操作均有配套的深色文字语义色。
- 我的页以实际档案、水平、朋友数、金币、积分和原入口组织纸卡，去掉桌面全息定位；不引入设计夹具里的虚构旅程计数。
- 设置、记忆、账号等功能页统一背景和纸面，保留全部实际开关、记忆纠正／遗忘、语音诊断和跳转；移除黑色金属标题章和摄影工作台背景。
- 剧情目录改为单一已有书店场景上的主线／城市故事纸卡。目录数量、完成记录、机票解锁及主线门槛仍取真实数据。剧情阅读使用与外出相同的选择和语义纸色。
- 角色资料用所在城市照片、头像和资料纸卡，保留完整人格、关系、恢复联系人及通话操作；不把旧夹具中的假好感度或假记忆写入账号。
- 年龄、国籍和剧情旅伴／旅行朋友类型继续显示在资料卡。订阅页、邮箱登录输入框及收藏夹搜索使用成对的自适应背景和文字色；收藏夹空态改为正常纸卡，不再沿用摄影桌面的透视排版。
- 角色学习保留实际星槽、挑战、记录与奖励流程，统一纸卡和操作，并将城市照片收进页首。全局“英语旅程”继续复用当前正式的水平选择／校准功能，不加入不存在的学习单元进度。
- 地图保留真实 MapKit 地球、城市选择和旅行流程，工具栏纸面与其他页面统一；没有使用静态图片假装地图。

底部纸栏复用原 `TabView` 的页面与导航生命周期，额外呈现统一的全宽按钮。重复点当前标签、从其他标签切回，均继续调用原来的返回根页面逻辑。未读计数与活动状态仍来自原状态。

## 复现与验收

构建及预览使用仓库脚本；工作树保存的旧设备 ID 不存在，本轮通过 `LINGOTRIP_SIMULATOR_UDID` 临时指定已有 iPhone 18 Pro，不修改工作树配置。

```sh
LINGOTRIP_SIMULATOR_UDID=659893A7-0822-43F4-8DA1-4A92E9C78814 Scripts/preview.sh build places-preview
LINGOTRIP_SIMULATOR_UDID=659893A7-0822-43F4-8DA1-4A92E9C78814 Scripts/test-ui.sh -collect-test-diagnostics never -parallel-testing-enabled NO -only-testing:LingoTripUITests/UnifiedVisualUITests -only-testing:LingoTripUITests/CityPlaceOutingTests
```

正式 App 截图放在本机 `build/unified-visual-implementation/`。保持模拟器原图，不生图、不修图；分组展示仅等比缩放。旧独立展示程序和 v1 图片保留为历史审阅材料，新版活动应以正式代码截图为准。

### 最终结果

- `Scripts/preview.sh build places-preview` 构建、签名、安装与启动成功。
- `20261031T154539Z-6003.xcresult`：6 通过，0 失败，0 跳过。覆盖主标签／搜索／资料／设置／地图返回、最大辅助字号、外出实际分支和暂停／杀进程恢复／足迹、聊天键盘收起后保留草稿、剧情选择／断点重启／结尾保存。
- `20261031T155416Z-7787.xcresult`：审查修正后 5 通过，0 失败，0 跳过。覆盖再次检查主页面实际导航、深色订阅／收藏夹搜索／邮箱输入、会员入口与未获取价格时禁用购买、示例方案切换（禁止购买）、剧情目录进入主线与城市章节。
- 独立审查发现的固定浅色背景／自适应文字冲突、深色控制图标、角色身份信息缺失均已修正。再次执行 iOS 架构检查与 `git diff --check`，均通过。
- 剧情阅读页保留原先摄影界面深色工具栏与局部浅色阅读区域的配置；正文和选择均呈现暖纸／墨绿，实装原图已复核。地图原生截图与测试确认没有重复底栏。

上述结果均在 `build/DerivedData/VerificationResults/`。原始测试截图位于 `verified-attachments/` 和 `review-attachments/`；`gallery.py` 复制原图并生成 `screenshots/`、`captures.json`、等比拼图与 HTML 图集。另补录正式代码的聊天、角色学习与深色设置截图；角色学习自身显示“示例进度，不计入账号”，聊天采用既有内存预览数据，不代表真实账号记录。

```sh
python3 docs/design/unified-2026-10-31/gallery.py --attachments build/unified-visual-implementation/verified-attachments --attachments build/unified-visual-implementation/review-attachments
```

本机图集：`http://127.0.0.1:8766/build/unified-visual-implementation/index.html`。未覆盖全量 UI、最小屏幕或真机；支付与在线 AI 不属于本轮视觉验证。

Computer Use 连接 Device Hub 返回 ScreenCaptureKit -3811，续作时也未提供 Computer Use 工具，因此使用定向 XCUITest 与原生截图；不将其写成手动交互验收通过。首次测试在诊断包导出阶段遇到磁盘空间不足，失败查询与会话日志保留在本机 `first-run-session.log`；清理仅涉及本轮损坏的生成结果包及可重建的 Xcode 模块、索引和包编译缓存，源码、数据库和旧的有效结果均保留。
