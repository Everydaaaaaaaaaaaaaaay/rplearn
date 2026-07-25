# 账号数据治理

## 可移植导出

已认证用户通过 `GET /v1/account/export` 取得一致性 JSON 快照。响应使用
`Cache-Control: no-store` 和附件下载头，不创建服务器临时文件，因此不会额外复制一份高敏感数据。
导出使用 PostgreSQL repeatable-read 只读事务，覆盖：

- 账号、绑定身份、设备会话和公开安全事件；
- 个人资料、金币账本、机票、城市解锁与旅行记录；
- 交易、订阅和权益的用户可读字段；
- AI 用量元数据、同步事件与审计操作。

导出明确排除密码摘要、刷新令牌、action token、Apple refresh token、IP/UA
摘要、计费原始 payload、AI prompt/回复、任务加密 payload 和服务端 Secret。
当前数据规模适合单次 JSON；加入语音、媒体或大体量会话后，应迁移为加密对象存储中的异步归档，
但不能降低本文件定义的字段排除和租户隔离要求。

## 删除状态机

客户端必须让用户显式选择：

- `immediate`：立即冻结账号并排队执行最终清除；
- `grace_period`：冻结账号并提供配置天数的冷静期，同时返回一次性高熵取消 token。

两种模式都要求正文确认值 `DELETE`。请求提交后，账号立即变为
`pending_deletion`，token version 递增，所有设备 session 和 refresh token
撤销，未发送的认证邮件任务取消。冷静期取消只能在 worker 开始处理前执行；成功取消后账号恢复
`active`，但旧会话不会恢复，用户必须重新登录。取消 token 只存 HMAC 摘要且使用后清空。

worker 领取到期任务后把请求置为 `processing`。如果账号绑定 Sign in with Apple，
worker 必须先解密所保存的 refresh token，并使用其原始 client ID 调用 Apple
`/auth/revoke`；暂时故障触发任务退避，不能跳过撤销直接清除。撤销成功后在事务中执行最终清除。

## 最终清除与必要留存

最终清除会级联删除身份、凭据、会话、资料、虚拟经济、旅行、同步、权益、AI
用量和未完成业务任务。已验证支付事实、订阅事实、provider event、审计事件和删除回执可能因财务、
反欺诈或安全义务按既定期限保留，但必须先执行：

- 去除用户外键和 App Account Token；
- 把计费/provider 原始 payload 替换为固定 redacted 标记；
- 清除审计与安全事件中的 IP 摘要、target ID 和 metadata；
- 删除账号邮件任务中的加密地址和 token；
- 删除回执只保留带独立命名空间 HMAC 的不可逆 user reference。

备份中的旧数据不做在线原地修改；它随备份保留期到期。任何隔离恢复环境都必须重新执行删除清单，
且不得把已删除账号恢复到生产可用状态。完成或取消的删除回执按
`ACCOUNT_DELETION_RECEIPT_RETENTION_DAYS` 清理，默认保留七年；正式期限需由上线地区的法律与
财务要求确认。

## 运行验证

- 每次发布运行导出敏感字段否定测试、会话撤销测试、取消重放测试和最终清除集成测试；
- `account.purge` 进入死信立即告警，人工不得直接把用户状态改回 active；
- 支持人员只能查看删除请求 ID、状态、时间和不可逆 reference，不得解密任务 payload；
- Apple 撤销的暂时网络/上游错误保持 `processing` 并重试；历史 credential 缺少 client ID
  时记录高优先级警告、继续履行数据删除，并按 Apple 手工撤销指引通知用户。
