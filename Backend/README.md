# LingoTrip Backend

后端是 TypeScript + Fastify 的模块化单体，部署为 API 和 Worker 两个进程。
PostgreSQL 保存权威业务状态，Redis 用于限流和短期协调，语音媒体存入私有 S3 兼容存储。

## 本地启动

需要 Node.js 24、pnpm 10 和 Docker：

```bash
pnpm install
cp .env.example .env
pnpm infra:up
pnpm db:migrate
pnpm dev

# 另开终端
pnpm worker
```

开发 API 默认监听 `http://127.0.0.1:8080`。PostgreSQL、Redis、Mailpit 和 MinIO
分别使用 `54329`、`63799`、`8025` 和 `9001`。

`.env` 不受版本控制。密钥、令牌、收据和用户内容不得写入源码、示例配置或日志。

## 目录

```text
src/server.ts          API 组合入口
src/worker.ts          持久任务 Worker
src/app/               Fastify、健康检查、错误与日志
src/config/            环境配置和启动校验
src/db/                Drizzle Schema、迁移与数据库连接
src/modules/           auth、account、domain、billing、ai、sync、
                       content、media、jobs、observability
migrations/            只向前数据库迁移
test/                  单元、集成与端到端测试
ops/                   部署、监控和容量脚本
```

HTTP Handler 只调用模块服务；数据库写入、幂等回执和同步事件应在同一事务中完成。
客户端提交领域操作，不提交金币、权益或解锁状态等最终值。

## 常用命令

```bash
pnpm check             # lint + typecheck + 单元测试
pnpm build
pnpm test:integration  # 需要 pnpm infra:up
pnpm test:e2e
pnpm production:check
pnpm infra:down        # 保留本地数据卷
```

主要开发端点：

- `/health/live`、`/health/ready`
- `/docs/openapi.json`（非生产）
- `/v1/auth`、`/v1/account`
- `/v1/me`、`/v1/travel`、`/v1/progression`
- `/v1/billing`
- `/v1/ai/completions`、`/v1/ai/stream`
- `/v1/content`、`/v1/sync`
- `/v1/media`

## 生产资料

日常业务开发不需要通读生产文档。修改对应领域时再按需查阅：

- [部署与密钥轮换](../docs/backend/DEPLOYMENT.md)
- [运行与事故处理](../docs/backend/OPERATIONS_RUNBOOK.md)
- [备份与恢复](../docs/backend/BACKUP_RESTORE.md)
- [指标与告警](../docs/backend/OBSERVABILITY.md)
- [安全边界](../docs/backend/THREAT_MODEL.md)
- [账号导出与删除](../docs/backend/ACCOUNT_DATA_GOVERNANCE.md)

平台和权威状态决策见
[`docs/adr/0001-production-backend-platform.md`](../docs/adr/0001-production-backend-platform.md)。
