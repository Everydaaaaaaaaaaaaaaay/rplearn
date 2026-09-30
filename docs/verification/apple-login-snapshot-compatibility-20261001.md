# Apple 登录后旅程加载兼容修复

日期：2026-10-01。修复提交及发布版本：`5af370ab04fd`。

## 原因与范围

用户截图显示“旅程尚未载入 / 服务器返回了无法识别的响应”。线上日志中 Apple 登录和
后续 `/v1/sync/snapshot` 均返回 HTTP 200，但客户端反复请求快照，没有进入内容加载阶段。

`a7b4c079` 清理旧小测时同时删除了服务端响应中的 `quizGloballyEnabled`。此前 iOS 的
`BackendUserProfile` 将它声明为非可选 `Bool`，因此整个状态快照解码失败。用移除该字段前的
原始 Swift 模型解析脱敏后的线上快照，复现了
`DecodingError.keyNotFound: state.profile.quizGloballyEnabled`。

本次只在资料响应映射中保留 `quizGloballyEnabled: false`。当前领域类型、数据库查询、
迁移和新客户端保持现状；旧小测保持关闭。快照、直接资料响应和资料更新共用这一映射。
未修改 iOS 源码，未发布 App Store 或 TestFlight 构建。

## 本地验证

- 类型检查和修改文件 ESLint 通过。
- 使用 Node 24.19.0 执行依赖边界检查，通过：248 个模块、682 条依赖。
- 针对资料兼容、Apple 认证组件、同步游标和主线奖励的 17 项测试通过。
- `pnpm exec vitest run --exclude 'test/integration/**'`：204 项通过、4 项跳过。
- 干净临时目录的 TypeScript 编译、发布包构建和 `git diff --check` 通过。
- 同一旧版 Swift 模型解析修复后的响应通过；上线后解析脱敏公网快照也通过。

默认 `pnpm test` 的非数据库测试同样通过，但 `learning-promotion.test.ts` 在收集阶段要求
显式隔离的 `DATABASE_URL`，导致默认命令失败。本次未运行数据库集成测试；修复未改变
查询、事务或数据库结构。默认 Node 23 不受依赖边界工具支持，该检查改用现有 Node 24 运行。

## 发布与线上验证

发布包：`lingotrip-backend-5af370ab04fd.tar.gz`。
SHA-256：`c470201509e81a41fa5ac272f5a3824714bb843c3d1f4a9d639fc1ee4a276318`。

沿用原生不可变发布脚本，校验远端包哈希后激活：
`/opt/lingotrip/releases/5af370ab04fd`。与上一发布版本相比没有新增迁移。
上一目录 `/opt/lingotrip/releases/b87cda3da1cb` 已确认保留。

API、Worker、Caddy 均为 active；公网 `/health/ready` 返回 `{"status":"ready"}`。
复用已有有效 Apple 会话的身份，仅在服务器进程内创建 30 秒验证令牌，读取以下接口；
不输出令牌、用户标识或原始用户资料，不创建账号或修改账号内容。

| 入口 | 接口 | 状态 | 兼容字段 |
| --- | --- | --- | --- |
| 本机 API | `/v1/sync/snapshot` | 200 | `state.profile.quizGloballyEnabled = false` |
| 本机 API | `/v1/me` | 200 | `profile.quizGloballyEnabled = false` |
| 公网 API | `/v1/sync/snapshot` | 200 | `state.profile.quizGloballyEnabled = false` |
| 公网 API | `/v1/me` | 200 | `profile.quizGloballyEnabled = false` |

## 验收边界

已验证线上响应与旧版客户端解码合同兼容。尚未取得反馈用户的具体构建号，也未在其真机
重新执行完整 Apple 授权及旅程进入流程。用户可在现有错误页点击“重试”后确认恢复。
