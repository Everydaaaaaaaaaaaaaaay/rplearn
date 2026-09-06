# 文档

文档只补充代码中不容易直接看出的稳定信息。模块 API、依赖和运行行为仍以代码、测试及
构建配置为准。

## 日常开发

- [`../README.md`](../README.md)：启动方式、仓库地图和最少开发约定。
- [`development.md`](development.md)：按任务查找入口与选择最小验证；无需逐项执行。
- [`system-verification.md`](system-verification.md)：功能验证矩阵、故障恢复、隔离端到端入口和未覆盖的真实环境边界。
- [`system-audit-2026-09-07.md`](system-audit-2026-09-07.md)：本轮检查发现的问题、修复与实际验证记录。
- [`architecture.md`](architecture.md)：客户端与后端的边界、数据流和改动入口。
- [`algorithm-complexity-audit.md`](algorithm-complexity-audit.md)：App 与各模块的算法复杂度、热点和优化门槛。

涉及具体领域时再读：

- [`journey-design.md`](journey-design.md)：主线路线、城市解锁和内容配置入口。
- [`story-rebuild-plan.md`](story-rebuild-plan.md)：新剧情施工流程、AI 美术一致性与全量发布门槛。
- [`story-direction-draft.md`](story-direction-draft.md)：已确认的创作方向与首站范围。
- [`story-london-production.md`](story-london-production.md)：伦敦日系可玩样章的脚本、资产、限制与验收记录。
- [`design-system.md`](design-system.md)：视觉方向与 DesignSystem 边界。
- [`realtime-voice.md`](realtime-voice.md)：端侧实时语音、低成本模型、生命周期与真机验收门槛。
- [`relationship-system.md`](relationship-system.md)：多维角色关系、好感度计算、时间衰减与校准边界。
- [`relationship-calibration-log.md`](relationship-calibration-log.md)：关系算法的历史实验、失败案例与验证证据。
- [`user-cost-evaluation.md`](user-cost-evaluation.md)：原生端到端用户成本评测、场景和证据解释。
- [`user-cost-study-results-2026-09-06.md`](user-cost-study-results-2026-09-06.md)：分层重复、额度对照和长聊天压力实测；附可复核数据。
- [`cost-pricing-proposal-2026-09-06.md`](cost-pricing-proposal-2026-09-06.md)：月度积分池、试运营价格及免费补贴的经营阈值（未上线）。
- [`model-credits.md`](model-credits.md)：统一模型积分、试行预算、定价测算与核对规则。
- [`../Backend/README.md`](../Backend/README.md)：后端本地开发。

## 按需部署

`backend/DEPLOYMENT.md` 只记录当前服务器的实际发布入口。备份、集群、长期迁移和合规流程
等尚未启用的设计不提前固化；需要了解演进历史时使用 Git。
