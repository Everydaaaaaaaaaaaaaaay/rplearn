# 文档索引

## 当前事实

- `HANDOFF.md`：当前功能、工程结构、Module 职责、构建方式与已知限制。
- `ui-redesign-plan.md`：已落地的视觉语言、信息架构与验收约束。
- `backend/ARCHITECTURE.md`：生产后端的模块边界、权威状态、同步、订阅、AI 与部署架构。
- `backend/IMPLEMENTATION_PLAN.md`：按独立提交拆分的后端与 iOS 迁移交付计划。
- `backend/THREAT_MODEL.md`：账号、支付、AI、数据与运维的威胁模型和上线安全门。
- `backend/DEPLOYMENT.md`：容器、迁移、滚动发布、Secret 与回滚基线。
- `backend/BACKUP_RESTORE.md`：PostgreSQL PITR、备份和隔离恢复演练。
- `backend/OPERATIONS_RUNBOOK.md`：SLO、告警、常见事故与日常作业。
- `backend/ACCOUNT_DATA_GOVERNANCE.md`：账号导出、即时/冷静期删除与必要留存边界。
- `adr/0001-production-backend-platform.md`：后端技术平台与关键架构决策。

工程 target 与依赖分别以根目录的 `project.yml` 和 `Packages/LingoKit/Package.swift` 为准；文档不重复充当构建配置。

## 历史记录

- `plan.md`：项目启动阶段的产品与技术计划。它保留当时的里程碑和决策背景，不描述当前实现。

新增文档时，应在这里标明它属于“当前事实”还是“历史记录”，避免出现多个互相冲突的事实源。
