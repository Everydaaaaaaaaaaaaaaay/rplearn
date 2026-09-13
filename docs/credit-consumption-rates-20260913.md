# 积分消耗倍率 — 2026-09-13

入口：https://coovingo.com/internal/admin/ai → 积分倍率。

- 全局默认 1×；单用户覆盖优先。批量填写最多 500 个 UUID，设置同一倍率，
  或恢复继承全局。范围 0–100，支持四位小数。0× 不扣用户积分；0.1× 扣原来的十分之一。
- 保存只影响新请求；reserve 时将倍率和策略版本写入账本，dispatch、finish、
  延后补账沿用该倍率。重放不会再次扣分。旧记录按 1× 处理，不重算历史。
- `settled_units` 是实际扣除积分单位，`raw_settled_units` 保存未乘倍率的成本。
  金额运算使用 bigint，在最小记账单位向上取整。运营报表沿用真实成本字段，
  新增单独的积分扣除汇总，不将折扣后的积分当作供应商费用。
- 自动任务预算及空回复转为产品承担的成本不打折。0× 用户可在余额耗尽后
  发起新请求和语音会话；平台的供应商实际费用、速率限制仍有效。
- 单独的 PostgreSQL 策略/覆盖/审计表（migration 0021），没有 Redis 配置缓存。
  管理员认证、版本冲突检测、幂等操作号和原因必填；不存在的用户令整批回滚。
  每次变更保留操作者、时间、修改内容和修改前状态；页面展示最近 20 次修改。
- 管理端 GET/PUT `/internal/admin/ai/credit-rates`。PUT 使用 `rateUnits`（倍率×10000），
  `scope`（global/users）、`userIds`、`expectedVersion`、`changeReason` 和 UUID
  `idempotency-key`。用户清除覆盖时 `rateUnits:null`。

## 验证

- TypeScript 类型检查、架构检查、变更文件 ESLint、release 构建通过。
- 23 项相关集成测试通过：积分账本、倍率覆盖/继承、并发版本、幂等、无效批量、
  0×、语音入口、自动任务、空回复、冻结倍率、补账及管理员鉴权。
  使用本机隔离 PostgreSQL/Redis，无真实 AI 调用。
- 全量普通测试 146 项通过；全量 lint 仍有原有的 build/bulk-console-preview.ts
  project-service 错误，以及 test/unit/encounter-weights.test.ts 非空断言错误。
  本次新增与修改文件的 lint 已单独通过。
- 浏览器验证：本机隔离后台全局 1→0.1→1 保存及审计成功；最终窄窗口检查表单
  与批量输入无重叠。服务端集成测试覆盖批量写入与恢复继承。

## 上线

版本 `credit-rates-20260913` 已激活，API/worker 就绪。公网页面包含新分区；
线上授权 GET 返回 200 / version 1 / globalRateUnits 10000 / 无用户覆盖，未授权 GET 401。
没有在生产运行模型测试或修改任何用户倍率。无需更新 iOS 即可应用服务端倍率。

上线前数据库备份位于服务器
`/opt/lingotrip/migration-backups/credit-rates-20260913/before.dump`，仅 root 可读。
上一版本 `settings-level-20260913` 保留。优先通过全局 1× + 清除用户覆盖停用倍率，
保留账单历史。若回退二进制，需保留新迁移的兼容性（旧版迁移数检查严格）；
不要还原数据库备份覆盖上线后的用户数据。
