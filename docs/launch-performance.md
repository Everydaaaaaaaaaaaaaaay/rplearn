# 启动性能记录（2026-09-14）

## 测量口径

使用同一台 iPhone 17 Pro 模拟器（iOS 26.5）、Xcode 27、Debug 构建，重复启动进程，
每组保留 5 个样本。测试入口为 `LaunchPerformanceTests/testLaunchToInteractiveMessages`。
使用本地内存账号、关闭主动消息刷新、后端指向本机关闭端口，以排除网络差异。

- `XCTApplicationLaunchMetric`：系统记录的启动耗时。
- `XCTClockMetric`：启动到搜索入口可点击的测试操作区间，包含 XCUITest 启动、等待与查询开销，
  不能当作纯渲染时间，也没有证明所有首屏数据已经加载完毕。
- 这是系统缓存保留情况下的进程重启，不是真机重启后的冷启动；没有真实登录与大历史数据库。
  5 次样本只报告均值和最大值，不据此推断 P95 或线上长尾。

基线版本：`6a9420c`。启动均值 0.981 秒，最大 1.129 秒；测试操作区间均值 4.307 秒。
仅完成本地加载调整后的启动均值 1.010 秒，最大 1.065 秒；测试区间均值 4.339 秒。
完成缓存路径与错峰调度后的启动均值 0.978 秒，最大 1.046 秒；测试区间均值 4.216 秒。
该差异处于本次运行波动范围，不能宣称普通启动平均耗时明显改善。

| 组别 | 系统启动样本（秒） |
| --- | --- |
| 基线 | 1.129、0.911、0.984、0.928、0.955 |
| 完成优化 | 1.046、0.950、0.983、0.920、0.992 |

本机测试结果位于 `build/DerivedData/VerificationResults/`：
基线 `20260914T001609Z-83630.xcresult`，完成优化 `20260914T002749Z-91939.xcresult`，
同步与订阅回归 `20260914T002623Z-90821.xcresult`。构建产物不提交。


## 已处理的启动压力

- 随包词典、语法与城市数据在后台任务读取；账号恢复可以同时进行。
- 账号目录准备、数据库打开及迁移、ModelActor 仓库创建移到后台；SwiftData 实体仍留在仓库中。
- 主角色种子解码移到后台；信息页档案、好友和会话摘要独立读取。
- 未访问的 Tab 不创建页面；首次访问后保留页面状态，点击 Tab 回根规则保持不变。
- 账号已恢复且本地快照完整、归属正确时，用户状态与内容先走缓存；首次登录和不完整缓存仍要求同步。
- 订阅激活先读取本地会员档位并建立交易监听，商品目录与交易恢复不再阻塞账号页面出现。
  购买与资产操作仍由原有服务端路径确认。

首屏后的任务错峰启动：约 1 秒刷新用户状态和内容（两项并发），2 秒同步订阅，
3 秒预热语音，4 秒同步头像，5 秒刷新主动消息。时间是各任务满足启动条件后的最早时点，
不是实时保证；任务仍受取消和账号生命周期约束，语音和商品页面保留按需加载能力。

这轮针对偶发慢启动的主要收益是移除了缓存路径上的串行网络等待。
原网络请求默认超时 30 秒；现在缓存激活和订阅延后激活测试明确断言启动阶段请求数为零。
首次账号恢复仍需要 Apple/服务器认证，首次内容引导也仍依赖网络，尚未测得这两类线上耗时。

## 回归与复测

```bash
DEVELOPER_DIR=/Volumes/data/Applications/Xcode.app/Contents/Developer \
  Scripts/test-ui.sh -parallel-testing-enabled NO \
  -only-testing:LingoTripUITests/LaunchPerformanceTests

DEVELOPER_DIR=/Volumes/data/Applications/Xcode.app/Contents/Developer \
  Scripts/test.sh -parallel-testing-enabled NO \
  -only-testing:LingoTripTests/BackendUserStateCoordinatorTests \
  -only-testing:LingoTripTests/BackendContentSyncCoordinatorTests \
  -only-testing:LingoTripTests/BillingControllerTests
```

账号同步、内容同步、订阅 17 项测试通过，覆盖缓存启动零请求、缺少缓存仍需联网、账号归属、
会员档位保留与随后正常加载商品。UI 覆盖重复启动、Tab/搜索切换、英语水平保存及侧滑返回。

App 日志以“启动耗时”标记会话恢复、等待随包资源、数据库打开、用户状态、内容激活、
账号工作区耗时，并区分缓存与同步路径；不记录账号标识或凭证。遇到特别慢的一次时，
优先取同一进程的这些阶段日志，区分网络等待、数据库迁移和本地加载，再做对应真机测量。
