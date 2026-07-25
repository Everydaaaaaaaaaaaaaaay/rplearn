# PostgreSQL 备份与恢复

## 目标

- 生产 RPO：不高于 15 分钟；
- 生产 RTO：不高于 60 分钟；
- 每日基础备份，连续 WAL 归档，至少 35 天 PITR；
- 每月至少一次在隔离账号和隔离网络中的完整恢复演练。

Redis 不作为权威业务备份。其恢复方式是创建空实例并让限流、nonce 和短期缓存自然重建。

## 备份

托管 PostgreSQL 必须开启：

- 自动基础备份与跨可用区存储；
- WAL 连续归档和时间点恢复；
- 静态加密、TLS、备份账户最小权限；
- 备份失败、WAL 延迟和存储容量告警。

发布前额外生成逻辑备份用于快速核验：

```bash
pg_dump --format=custom --no-owner --no-acl \
  --dbname="$DATABASE_URL" --file=lingotrip-predeploy.dump
```

备份文件属于敏感生产数据，只能进入加密对象存储，不能提交仓库或发送到聊天。

## 隔离恢复演练

1. 新建与生产版本相同的隔离 PostgreSQL，禁止应用生产凭据访问。
2. 从目标时间点创建 PITR 实例，或使用 `pg_restore --clean --if-exists` 恢复逻辑备份。
3. 以只读凭据执行一致性检查：
   - 迁移版本与发布镜像一致；
   - 金币投影等于 `coin_ledger` 累计；
   - 同一 provider/environment 的交易、订阅和事件唯一；
   - entitlement 不跨用户关联；
   - `sync_heads.last_sequence` 不小于该用户最大 change sequence；
   - 所有外键有效且关键表行数处于预期范围。
4. 使用隔离 Redis 启动同 digest API，验证 readiness、登录、快照、权益和 AI mock canary。
5. 记录实际 RPO/RTO、校验结果和恢复操作者，销毁隔离数据。

## 生产恢复

发生误删或不可逆数据损坏时，优先暂停写流量。按最后已知正确时间点创建 PITR
副本，在副本完成一致性验证后通过连接串切换；不要直接覆盖原实例。切换后保留原实例只读，直至事故复盘和数据对账完成。
