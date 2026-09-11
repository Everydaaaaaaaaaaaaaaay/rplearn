# 后端部署

当前开发服务运行在 `rplearn.haruyuki.cn`，采用 Ubuntu 原生 systemd，不使用 Docker。
Caddy 是唯一公网入口；`PUBLIC_HOST` 提供 App API，`ADMIN_HOST` 仅提供受管理员鉴权保护的
AI 控制台。API、Worker、PostgreSQL 17、Redis、MinIO 和 Mailpit 均只在本机监听。

## 首次初始化

首次初始化时，可将后端源码放到 `/opt/lingotrip/backend`，再运行：

```bash
cd /opt/lingotrip/backend
./ops/native-server/generate-production-env.sh
./ops/native-server/bootstrap-ubuntu.sh
./ops/native-server/install-services.sh
```

`.env.production` 是不受版本控制的唯一源配置。初始化脚本把它拆分成
`/etc/lingotrip/` 下各服务可读的最小环境文件，并创建独立的数据库迁移和运行时账号。
已有配置不会自动覆盖。

## 发布

发布包在开发机编译，只包含 `dist`、当前迁移基线和生产依赖清单：

```bash
cd Backend
./ops/native-server/package-release.sh <commit>
scp build/lingotrip-backend-<commit>.tar.gz root@<server>:/tmp/
ssh root@<server> \
  "/opt/lingotrip/ops/native-server/deploy.sh /tmp/lingotrip-backend-<commit>.tar.gz <commit>"
```

线上运维脚本安装在 `/opt/lingotrip/ops/native-server`，与发布目录分开；旧 `/opt/lingotrip/backend` 链接可能指向已清理的历史目录，不能作为发布入口。发布包在独立临时目录编译，不携带已删除源码的旧编译产物或 macOS 资源分叉文件。

部署脚本会安装内容寻址的生产依赖、执行数据库迁移、收紧运行时权限、原子切换
`/opt/lingotrip/current`，然后重启 API 和 Worker 并检查 readiness。应用启动失败会切回
上一个发布目录；数据库结构不自动回滚。

## 最近发布验证

2026-09-11：发布 `f4977bb`，上一版本 `8b2ef54` 保留。发布包 SHA-256：
`aa63029d61fe3de2bdfbc68feb5dcd3393d9e982a8478c0cd7ab511c1d2f478e`。
GLM 聊天改为 minimal 思考、总输出预算下限 512（受路由上限约束）；空正文记为失败并由服务承担。
API / Worker active，公网 readiness 正常。使用当前发布的真实 OpenRouter 流式适配器验证，
收到非空正文及 done，实际输出 30 tokens。无新增数据库迁移。
详见[空回复修复记录](../chat-empty-reply-fix-2026-09-11.md)。新版 iPhone 13 开发包已覆盖安装成功。

2026-09-11：发布 `8b2ef54`，上一版本 `c36296c` 保留用于回滚。发布包 SHA-256：
`e978bc6c87150e63861328c96f96fc61e235f3e2873e904a808c5e8ad7b45709`。
此次只改 OpenRouter 会话粘性路由，无新增迁移或生产依赖；API / Worker 均 active，
公网 `/health/ready` 返回 ready。对当前发布的客户端模块注入模拟 fetch，验证跨轮 session_id
一致及缓存 token 解析正常，未追加真实供应商调用。此前 8 次 GLM 缓存对照见
[费用优化与缓存实测](../ai-cost-optimization-2026-09-11.md)。
小测合并、记忆策略及提示词重排仍需安装新版 iOS App。

2026-09-11：发布 `c36296c`，上一版本为 `credit-fix-30fa8b4`。发布包 SHA-256：
`66fd7928d253ee3a74685d053b94368d28adf9f4d79a0305adb3da8b87468cf4`。
此次无迁移文件变更，沿用现有生产依赖。API / Worker 均为 active，readiness 返回 ready。
在已登录的 Chrome 页面 `https://coovingo.com/internal/admin/ai` 刷新数据后，
确认任务路由只剩 9 项，不再显示整句翻译和语音反馈；其他任务仍使用 GLM 5.3 Flash。
语音反馈的旧客户端请求会在模型调用与额度操作前被拒绝，历史账单和配置记录保留。
这次上线的是后端；Apple 本地整句翻译和客户端点评卡移除需安装新版 iOS App。

## 数据保护

保留现有账号、媒体和迁移历史；服务端迁移只追加，SwiftData 使用版本化迁移。
迁移失败停止发布并保留原库，不能以清库恢复。破坏性操作需单独明确授权和可恢复备份。
隔离测试环境可使用一次性数据库，不能连接开发或生产数据。

备份、恢复与线上开关的实际状态需在部署任务中核实；历史“尚无真实用户”的假设不再作为
重置数据或跳过兼容的依据。

## 日常检查

```bash
systemctl status lingotrip-api lingotrip-worker lingotrip-caddy \
  lingotrip-minio lingotrip-redis postgresql
journalctl -u lingotrip-api -u lingotrip-worker --since -1h
curl --fail https://rplearn.haruyuki.cn/health/ready
```

Mailpit 用于捕获开发邮件。Apple 登录和计费是否启用以部署环境为准；启用前核实外部凭据。密钥、完整
环境文件和用户内容不得进入 Git、命令参数、聊天记录或日志。

启用原生 Apple 登录前，在 Apple Developer 中为 App ID 打开 Sign in with Apple，并创建对应
私钥。服务器环境至少填写 `APPLE_CLIENT_IDS`、`APPLE_TEAM_ID`、`APPLE_KEY_ID`、
`APPLE_PRIVATE_KEY_BASE64`、`APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64` 和
`APPLE_CREDENTIAL_KEY_VERSION`，再将 `APPLE_AUTH_ENABLED` 设为 `true`；纯原生 iOS 登录不填
`APPLE_REDIRECT_URI`。加密密钥和版本需要随备份保留，轮换前必须保证旧版本仍可解密。
发布后分别用新 Apple 账号、隐藏邮箱账号、已有邮箱账号的显式绑定、另一设备会话撤销、
解除 Apple 登录和 App 内删除账号做真机验收；不得把模拟器或替身测试当作 Apple 线上验收。

## NPC 图库与后台补齐

已验收头像以内容哈希命名存放在 `/srv/lingotrip/npc-avatars`，由 Caddy 的 `/npc-avatars/*` 路由提供公开 HTTPS 图片与长期 immutable 缓存。该目录只放公开 PNG；清单、来源记录和测试状态保存在非公开目录。图片上传后逐张校验 SHA，先确认公开 URL 可用，再导入清单；已有同名文件哈希不符时应拒绝覆盖。

```bash
# 在服务器上运行，环境值只由 Node 读取，不展开到命令参数。
/opt/lingotrip/runtime/bin/node \
  --env-file=/etc/lingotrip/backend.env \
  --env-file=/etc/lingotrip/release.env \
  /opt/lingotrip/current/dist/cli/import-npc-avatars.js /absolute/manifest.json
```

导入在同一数据库事务中唤醒待匹配请求。新版 `lingotrip-worker` 每分钟处理到期队列；App 登录进入前台后自动领取绑定结果。服务器发布不会替用户安装新版 iOS 客户端。

2026-09-06 的 0006/0007 迁移只新增图库画像、匹配记录、待匹配表及调整头像共享索引；既有 29 个账号未重置。该次临时数据库快照与旧 Caddy 配置保留在 `/opt/lingotrip/migration-backups/npc-6f307a4-20260906`。旧程序启动要求迁移数量完全一致，因此另备了 `/opt/lingotrip/releases/npc-6f307a4-fallback`（原程序配合当前迁移文件）的回退包；普通旧发布目录不能在新迁移后直接重启。该回退包仅适用于本次兼容的迁移，后续发布不能机械复用。
