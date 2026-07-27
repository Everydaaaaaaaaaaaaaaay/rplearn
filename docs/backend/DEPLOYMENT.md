# 后端部署

当前开发服务运行在 `rplearn.haruyuki.cn`，采用 Ubuntu 原生 systemd，不使用 Docker。
Caddy 是唯一公网入口；API、Worker、PostgreSQL 17、Redis、MinIO 和 Mailpit 均只在本机
监听。

## 首次初始化

服务器上的项目目录为 `/opt/lingotrip/backend`：

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
  "/opt/lingotrip/backend/ops/native-server/deploy.sh /tmp/lingotrip-backend-<commit>.tar.gz <commit>"
```

部署脚本会安装内容寻址的生产依赖、执行数据库迁移、收紧运行时权限、原子切换
`/opt/lingotrip/current`，然后重启 API 和 Worker 并检查 readiness。应用启动失败会切回
上一个发布目录；数据库结构不自动回滚。

## 开发期数据策略

产品尚未发布且没有真实用户，因此服务端和 SwiftData 都只保留当前基线：

- 数据模型变化时可在停服后重置测试数据库和媒体对象；
- 不维护历史迁移兼容、PITR、定时备份或长期备份保留；
- 破坏性操作前只按当次需要创建临时快照；
- 正式发布前冻结首个公开基线，再补迁移、备份和恢复演练。

这项策略只适用于无真实用户阶段。一旦开始邀请需要保留数据的测试用户，就必须先调整
本节并恢复持久数据保护。

## 日常检查

```bash
systemctl status lingotrip-api lingotrip-worker lingotrip-caddy \
  lingotrip-minio lingotrip-redis postgresql
journalctl -u lingotrip-api -u lingotrip-worker --since -1h
curl --fail https://rplearn.haruyuki.cn/health/ready
```

Mailpit 仍只负责捕获开发邮件。Apple 登录和计费在外部凭据齐全前保持关闭。密钥、完整
环境文件和用户内容不得进入 Git、命令参数、聊天记录或日志。
