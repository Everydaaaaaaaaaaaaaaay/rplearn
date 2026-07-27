# LingoTrip Backend

后端是 TypeScript + Fastify 模块化单体，运行 API 和 Worker 两个进程。PostgreSQL 保存
权威状态，Redis 只保存可丢失的短期状态；媒体存储与邮件服务按功能需要启用。

## 本地启动

需要 Node.js 24、pnpm 10、PostgreSQL 17 和 Redis。macOS 可直接使用 Homebrew 服务：

```bash
brew install postgresql@17 redis
brew services start postgresql@17
brew services start redis
createdb lingotrip

pnpm install
cp .env.example .env
pnpm db:migrate
pnpm dev
```

另开终端运行 `pnpm worker`。若本机数据库账号或端口不同，只需调整 `.env` 中的
`DATABASE_URL` 和 `REDIS_URL`。媒体上传和邮件联调时再按需启动本机 MinIO 与 Mailpit；
普通业务开发不依赖它们。

`.env` 不受版本控制。密钥、令牌、收据和用户内容不得写入源码、示例配置或日志。

## 目录

```text
src/server.ts          API 组合入口
src/worker.ts          后台任务入口
src/app/               Fastify、健康检查、错误与日志
src/config/            环境配置
src/db/                Drizzle Schema 和数据库连接
src/modules/           业务模块
migrations/            当前开发期数据库基线
test/                  单元、集成与端到端测试
ops/native-server/     当前 systemd 部署脚本
```

HTTP Handler 只调用模块服务；数据库写入、幂等回执和同步事件应在同一事务中完成。
客户端提交领域操作，不提交金币、权益或解锁状态等最终值。

## 常用命令

```bash
pnpm check
pnpm build
pnpm test:integration  # 需要本机 PostgreSQL、Redis；媒体用例还需要 MinIO
pnpm test:e2e
pnpm db:generate
pnpm db:migrate
pnpm db:studio
```

开发 API 默认监听 `http://127.0.0.1:8080`，OpenAPI 位于 `/docs/openapi.json`。
生产发布只需按需阅读[部署说明](../docs/backend/DEPLOYMENT.md)。
