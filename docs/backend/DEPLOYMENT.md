# 后端部署基线

## 运行拓扑

生产环境使用无状态 API 副本、托管 PostgreSQL、托管 Redis、SMTP
提供商和外部 Secret Manager。PostgreSQL 是唯一权威业务存储；Redis
丢失只影响短时 challenge、限流窗口等可重建数据。公网入口必须在负载均衡或 Ingress
终止 TLS 1.2+，容器自身不直接暴露公网端口。

`Backend/Dockerfile` 生成 Node 24、非 root、只含生产依赖的镜像。部署镜像必须使用 digest
固定，不使用浮动 tag。`Backend/ops/kubernetes` 是最低安全基线；上线时由部署系统注入
ConfigMap 和 Secret，不把值写进 manifest。

## 发布顺序

1. CI 完成格式、lint、类型、单元测试、真实 PostgreSQL/Redis 集成测试、生产依赖审计和镜像构建。
2. 为镜像生成 SBOM，并由镜像扫描器阻止 critical/high 且无豁免的漏洞。
3. 确认最近一次 PostgreSQL 基础备份和 WAL/PITR 流连续可用。
4. 使用与 API 完全相同 digest 的一次性 Job 执行 `node dist/cli/migrate.js`。
5. 等迁移 Job 成功，再滚动更新 API；readiness 失败的 Pod 不接收流量。
6. 验证 live、ready、metrics、注册/刷新、同步、计费沙盒通知与 AI canary。
7. 观察错误率、P95/P99、数据库连接、Redis 错误和 AI 上游错误至少一个正常业务峰值窗口。

迁移只允许向前追加，并在至少一个发布窗口内保持旧应用版本可读。破坏性列删除、重命名和
`NOT NULL` 收紧必须按 expand → backfill → contract 跨多个版本完成。

## 必需 Secret

- PostgreSQL、Redis、SMTP 凭据；
- Ed25519 JWT 私钥、公钥、key ID 与 token HMAC pepper；
- DeepSeek API key；
- metrics 独立 bearer token；
- Apple 登录私钥与 Apple credential AES-256-GCM key；
- 启用 Apple Billing 时的 App Apple ID 和 Apple PKI 根证书。

生产配置校验采用 fail-closed：缺少数据库、Redis、SMTP、持久 JWT、DeepSeek 或 metrics
保护凭据时进程拒绝启动。Secret 只通过运行时环境或挂载式 Secret
注入，禁止进入镜像层、CI 日志、崩溃报告或聊天记录。

## 回滚

应用回滚只切回上一镜像 digest，不回滚已执行的数据库迁移。若新版本产生不可兼容写入：

1. 先停止新版本流量；
2. 启用对应功能开关或只读保护；
3. 回滚到仍兼容当前 schema 的上一 digest；
4. 以新迁移修复数据，不执行手工 `DROP` 或 migration table 篡改。

若数据库数据已被破坏，按恢复手册在隔离实例执行 PITR，验证后通过受控切换恢复服务。

## 本地完整容器联调

```bash
cd Backend
DEEPSEEK_API_KEY='从本机安全环境注入' docker compose --profile app up --build --wait
```

API 为 `http://127.0.0.1:8080`，Mailpit 为
`http://127.0.0.1:8025`。Compose 开发配置使用临时 JWT
密钥，容器重启会使现有 access token 失效；生产绝不能使用这一开发行为。
