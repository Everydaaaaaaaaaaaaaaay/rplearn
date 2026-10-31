# 赴约系统实施计划

> For agentic workers: use superpowers:subagent-driven-development for bounded tasks, followed by specification and code review. Continue within this chat.

**Goal:** 恢复原有界面，在现有活动系统旁接入聊天约定、动态赴约、独立总结及有证据的关系和共同经历记忆。

**Architecture:** 沿用 docs/appointment-story-design-2026-10-30.md 已讨论的业务与叙事边界。PostgreSQL 保存约定、不可变故事块、选择、幂等操作及结算；App 装配独立 AppointmentFeature，Feature 不互相依赖。实拍背景按城市独立慢速轮播，使用既有剧情阅读样式。

**Tech Stack:** TypeScript/Fastify/PostgreSQL/Zod，SwiftUI/BackendKit/DomainKit/PersistenceKit。

## 顺序与责任

- [ ] 撤回 0c456eb4，构建原有 App、检查架构与差异，独立提交恢复。保留该提交之前的活动重构。
- [ ] 后端：先用单元及隔离数据库测试建立双方确认、当地时间/DST、窗口、重复请求、并发选择及重复结算约束；实现 appointments 领域、增量迁移、AI 生成/审核路由、操作租约和恢复。模型输出不含好感绝对值，已接受事件与选择同事务保存。
- [ ] iOS：新增 BackendKit Sendable 契约与 AppointmentFeature；列表、原剧情式阅读、自定义输入、失败重试、暂停恢复、历史、独立总结。提交前持久化 commandId，离线可读、不本地续写。
- [ ] App 与聊天：活动页提供赴约入口；聊天消息存储/同步后检测双方确认并呈现约定卡，卡片与活动页打开同一记录。将已接受经历和约定状态投影到后续聊天上下文。
- [ ] 结算：只采用已接受路径审阅，永久幂等事件账本；关系采用现有算法与并发安全投影，记忆保留赴约来源且可编辑/遗忘，回放不重写。审阅失败明确待结算。
- [ ] 照片：复用准备包伦敦运河/公园/街区原始照片及署名；核查其他城市题材与来源，未验收素材不发布。缺图显示真实的城市素材待准备状态。
- [ ] 核对功能规格与代码质量；运行 Backend typecheck/lint/architecture、定向单元与隔离集成、相关 Xcode 宿主/UI 测试。以正式生成接口执行样章和对抗输入检查，记录自由输入的实际后果。
- [ ] 按增量迁移部署后端并检查线上业务；运行 Scripts/preview.sh 安装最新 App，留在模拟器供查看。每个完成验证的逻辑改动独立提交，保留用户数据与历史迁移。

## 共同接口边界

端点前缀 /v1/appointments。list/detect 返回 appointments 和 serverNow；detail/start/choices/cancel 返回 appointment、session、summary 和 serverNow。所有写操作带 commandId 和 expectedRevision；下一块接受才增加 revision。开始使用服务端时间与应用城市，开始后不受首次入场窗口过期影响。

检测读取服务端实际角色与消息，以双方消息证据建约；含糊或单方提议不自动确认，改期必须重新达成一致。约定主题、地点、城市、IANA 时区和当地时间必须完整。正文和选项同次生成，接受之前审核身份、事实、用户自主和边界；最多一次定向修复，失败保留原选择。

首轮目标范围为可变的短至长相处（自然告别可提前结束，按块上限保护成本）；不把未选路径、生成草稿或用户的系统命令写为共同事实。总结列出真实选择和后果，关系变化包括负向/零/正向/待结算，不能因迟到、退出或英语错误扣分。
