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
src/db/                共享 Schema、数据库连接与迁移入口
src/modules/           业务模块
dependency-cruiser.cjs 本地模块边界规则
migrations/            只追加的 PostgreSQL 版本迁移
test/                  单元、集成与端到端测试
ops/native-server/     当前 systemd 部署脚本
```

HTTP Handler 只调用模块服务；数据库写入、幂等回执和同步事件应在同一事务中完成。
客户端提交领域操作，不提交金币、权益或解锁状态等最终值。
模块通过 `types.ts`/service 暴露能力，不读取其他模块的 `repository.ts` 或 `schema.ts`；
`pnpm architecture` 会检查跨模块实现泄漏、基础设施反向依赖和循环依赖。

## 常用命令

```bash
pnpm check
pnpm architecture
pnpm build
pnpm test:integration  # 需要本机 PostgreSQL、Redis；媒体用例还需要 MinIO
pnpm test:e2e
pnpm db:generate
pnpm db:migrate
pnpm db:studio
pnpm npc-avatars:import -- /absolute/path/npc-avatars.json
```

数据库迁移只追加、不改写已经执行的历史文件；部署时先运行 `pnpm db:migrate`，迁移失败应停止发布，不能通过清空数据库绕过。`migrations/0004_npc_registry.sql` 建立公共 NPC、11 位旅伴号、头像池和用户私有关系映射。

头像文件先放入 HTTPS 对象存储/CDN，使用 `npc-avatars.example.json` 的 version=2 格式记录文化标签、图片家族、SHA-256 与授权审核信息。`npc-avatars:import -- manifest.json --dry-run` 校验格式，正式导入验证实际图片字节；`npc-avatars:audit -- manifest.json npc-avatar-personas.example.json` 输出文化覆盖与连续偶遇耗尽报告。0006 迁移保留历史头像，新增按用户永久绑定；旅伴号查询改为认证接口。详见 [文化头像方案与上线门槛](../docs/npc-avatars.md)。

开发 API 默认监听 `http://127.0.0.1:8080`，OpenAPI 位于 `/docs/openapi.json`。
生产发布只需按需阅读[部署说明](../docs/backend/DEPLOYMENT.md)。
