# LingoTrip Backend

生产后端的模块化单体。架构和分阶段计划见：

- [`../docs/backend/ARCHITECTURE.md`](../docs/backend/ARCHITECTURE.md)
- [`../docs/backend/IMPLEMENTATION_PLAN.md`](../docs/backend/IMPLEMENTATION_PLAN.md)
- [`../docs/backend/THREAT_MODEL.md`](../docs/backend/THREAT_MODEL.md)

## 本地启动

需要 Node.js 24 和 pnpm 10：

```bash
pnpm install
cp .env.example .env
pnpm infra:up
pnpm db:migrate
pnpm dev
```

`.env` 不受版本控制。不要把 AI、数据库、JWT 或第三方凭据写入示例文件、源码或日志。

## 检查

```bash
pnpm check
pnpm build
pnpm test:integration
```

`test:integration` 需要先运行 `pnpm infra:up`。PostgreSQL 映射到本机
`54329`，Redis 映射到 `63799`，避免占用常见的默认端口。

开发服务默认监听 `http://127.0.0.1:8080`：

- `GET /health/live`
- `GET /health/ready`
- `GET /docs/openapi.json`（仅非生产环境）

停止本地依赖使用 `pnpm infra:down`。该命令默认保留数据库卷；只有显式执行
`docker compose down --volumes` 才会删除本地开发数据。
