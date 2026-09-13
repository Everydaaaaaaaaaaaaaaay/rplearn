# 账号、订阅与英语水平修复（2026-09-13）

## 界面

个人资料从半屏弹窗改为“我的”内独立页面，沿用收藏／设置的 SceneNavigationContainer 与工作台背景、纸张组件。身份信息、账号安全、退出登录分别建立层级。复用既有背景图片，没有新增或修改摄影资产。
原“账号”场景入口改为“订阅”，金币入口也打开订阅页。订阅页分为当前方案与余额、订阅计划、金币充值、管理／恢复购买与用量入口，价格取自既有 BillingController 商品，不虚构可购买方案。
记忆入口、路由与无障碍入口均移除 DEBUG 限制，TestFlight 和正式构建也可进入记忆档案。

## 保存失败原因与处理

重启后已有本地档案与同步游标，activate 只拉取增量；无新变更时并未初始化内存 snapshot，updateProfile 因而在发送 PATCH 前返回 invalidResponse。现在无 snapshot 时恢复权威快照，离线激活后首次修改也会尝试恢复；不使用本地成功提示掩盖服务器失败。
英语水平选择页点击完成直接提交，成功后返回并应用难度，保存期间禁止重复选择；失败保留选择与错误提示。移除“直接应用”按钮。
另外补齐后端 kindergarten 枚举：档案、内容和同步验证一致，追加 0020 迁移，保留全部既有枚举与用户数据。

## 验证与发布

- BackendUserStateCoordinatorTests：9 项通过，含“重启后无增量变更仍可修改英语水平”。
- UI：账号／订阅／记忆独立页面导航通过；选择小学二年级后点完成立即返回并显示新等级通过。
- 已检查模拟器账号和订阅截图；商品不可用状态显示真实目录状态。没有执行付费购买。
- 后端 TypeScript 类型检查、变更文件 ESLint 通过；独立 PostgreSQL 55439 与 Redis 56389 上 3 项 domain 集成测试通过，含新增迁移与幼儿启蒙／小学等级保存。测试服务已停止。
- 真机签名构建通过。Xcode 测试结果：/tmp/settings-unit-tests-v2.xcresult、/tmp/settings-ui-final.xcresult、/tmp/settings-level-ui.xcresult。
- 后端已发布 settings-level-20260913，前版 ai-glm-20260913 保留。API／Worker active，公网 readiness ready，线上枚举查询确认 kindergarten 与 primary2 均存在。未修改真实用户等级进行探测。

客户端变更需安装新版 App；已有 TestFlight 安装不会因为后端部署自动获得新页面或记忆入口，仍需后续上传新的测试构建。

## 订阅管理入口跟进（同日）

移除应用内 StoreKit manageSubscriptionsSheet，改为明确的“在 App Store 管理订阅”链接，打开 Apple 官方账户订阅地址。系统拒绝打开时提供设置路径；不读取、代填或保存 Apple 购买账号。此调整避免内嵌系统页持续占据应用，但不能保证 Apple 服务的登录／加载一定成功；未进行真实账户登录或付费验证。测试环境的购买账户与应用登录会话相互独立。
场景订阅入口 contentScale 从 1.08 调至 0.92（缩小约 15%），实心图标改为轮廓版本，点击范围和背景均不变。已检查 /tmp/subscription-management-images 中的实际模拟器截图，导航 UI 测试通过（/tmp/subscription-management-ui.xcresult）。
