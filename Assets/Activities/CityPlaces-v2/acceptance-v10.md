# 城市活动真实客户端入口修复 v10

2026-11-16，用户反馈真机普通城市活动入口白屏，提示“城市信息暂时无法读取，请重试。”，重复点击仍失败。本次修复并完成线上真机入口复验。

## 原因与修复

活动网关的目录、进行中外出及进度操作使用 `/v2/`。`BackendClient.perform` 的版本检查仍只接收 `/v1/`，因此实际请求在发出前抛出 `invalidResponse`，活动页进入统一错误状态。重试重复经过同一检查。

客户端普通 HTTP 请求现在接收 `/v1/` 与 `/v2/`。回归测试直接调用实际 `BackendClient` 的活动网关方法，使用测试传输层记录 HTTP 请求。登录账号与游客分别覆盖目录、空与非空进行中记录、历史、按 ID 读取、开始，以及 read、presented、choice、complete、abandon 操作，同时检查鉴权、目录版本参数与请求方法。四种未支持路径的拦截也有覆盖。

[v9](acceptance-v9.md) 的普通入口测试使用离线网关，遗漏了实际客户端底层版本检查。该版真实服务请求链路的验收缺口由本次复验补齐。照片、来源许可、裁切和界面布局沿用 v7–v9 的证据。

## 验证

| 范围 | 结果与证据 |
| --- | --- |
| 修复前回归 | 登录与游客两个参数运行均因 `invalidResponse` 失败。结果包 `20261116T124320Z-99518.xcresult` |
| 修复后原生测试 | `BackendClientTests`、`PlaceOutingProgressTests`、`CityOutingModelTests` 共 21 项通过，0 失败、0 跳过。结果包 `20261116T124523Z-279.xcresult` |
| 架构与差异 | `Scripts/check-architecture.sh --ios`、`git diff --check` 通过 |
| 模拟器 | 通过 `Scripts/preview.sh preview world-preview` 安装最新测试构建并保留完整世界预览 |
| 真机生产入口 | iPhone 13、iOS 27.2 的签名构建、安装与启动成功，Device Hub 原生截图确认伦敦泰晤士河南岸、照片、箭头和透明描边胶囊均显示 |

两份结果包位于 `build/DerivedData/VerificationResults/`。本次日志、汇总、真机安装和启动回执位于 `build/activity-v2-client-fix-20261116/`。首次新增测试编译遇到嵌套宏展开错误，修订测试后完成上述修复前后对照。

真机使用 `com.tiantian.lingotrip`，连接正式 `https://rplearn.haruyuki.cn`，恢复设备现有登录会话。启动时仅设置真实鉴权、活动页面目的地及线上后端地址，活动目录由实际 `BackendClient` 请求服务端。

20 时 51 分的原生截图为 `build/activity-v2-client-fix-20261116/device-live-activity.png`，1170×2532，SHA256 为 `c1793c385c885f60dc1753ac369a7a40b1f33821d50f97e93f05443fcf139193`。Computer Use 已查看原图，手机保留在该页面。

## 结论与范围

本次用户报告的城市读取失败已修复，真实鉴权和活动目录加载通过。真实手机本轮检查范围为现有账号的城市活动加载，全部外出操作的请求编解码与鉴权由上述原生回归覆盖。全量真人账号迁移和语音音质继续沿用 v9 的待测边界。
