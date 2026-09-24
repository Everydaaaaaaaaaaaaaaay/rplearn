# 文档索引

按任务阅读。必要工程规则集中在 [AGENTS.md](../AGENTS.md)，命令与实现以代码、测试和
构建配置为准。领域文档补充设计意图，日期报告保留当时证据，不构成当前提交的固定流程。

## 开发与当前设计

| 任务 | 入口 |
| --- | --- |
| 启动与仓库地图 | [项目 README](../README.md)、[后端 README](../Backend/README.md) |
| 选择验证 | [开发速查](development.md)、[功能验证矩阵](system-verification.md) |
| 模块、账号与同步边界 | [架构](architecture.md) |
| 登录入口、账号隔离与订阅 | [账号与定价策略](account-access-and-pricing-policy-2026-09-10.md)；商店价格配置不等于已生效 |
| 城市与剧情 | [旅行设计](journey-design.md)、[出发之后](departures-collection.md)、[剧情美术验收](verification/departures-art.md) |
| 场景与活动 | [必要视觉验收](activity-scene-visual-acceptance.md)及其中最新记录、[相遇流程](activity-encounter-journey-plan.md) |
| 视觉与语音 | [设计系统](design-system.md)、[实时语音](realtime-voice.md) |
| 对话成长原生原型 | [入口、规则、循环记录与验证边界](learning-program/conversation-prototype-2026-09-22.md) |
| 学习系统历史资料（当前方案已撤下） | [总方案](learning-program/README.md)、[执行工作流](learning-program/workflow.md)、[进度账本](learning-program/status.md) |
| NPC 与关系 | [人物多样性](npc-persona-diversity.md)、[关系系统](relationship-system.md) |
| 积分与成本 | [模型积分](model-credits.md)、[成本评测](user-cost-evaluation.md) |
| 部署与模型运营 | [部署](backend/DEPLOYMENT.md)、[AI 控制面](backend/AI_CONTROL_PLANE.md)；仅在对应任务使用 |

## 历史与证据

- [系统审计 2026-09-07](system-audit-2026-09-07.md)、[复杂度审计](algorithm-complexity-audit.md)：当时发现和验证范围。
- [剧情重构原计划](story-rebuild-plan.md)、[创作方向](story-direction-draft.md)、[伦敦样章](story-london-production.md)：制作背景；当前正式篇目见《出发之后》。
- [关系校准](relationship-calibration-log.md)、[成本实验结果](user-cost-study-results-2026-09-06.md)、[早期定价提案](cost-pricing-proposal-2026-09-06.md)：实验数据与假设，不代表当前权益或售价。

历史验收保留对应版本和未解问题；未变化证据可复用，修复状态以该领域最新记录为准。
