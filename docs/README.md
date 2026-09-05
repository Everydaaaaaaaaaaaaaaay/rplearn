# 文档

文档只补充代码中不容易直接看出的稳定信息。模块 API、依赖和运行行为仍以代码、测试及
构建配置为准。

## 日常开发

- [`../README.md`](../README.md)：启动方式、仓库地图和最少开发约定。
- [`architecture.md`](architecture.md)：客户端与后端的边界、数据流和改动入口。
- [`algorithm-complexity-audit.md`](algorithm-complexity-audit.md)：App 与各模块的算法复杂度、热点和优化门槛。

涉及具体领域时再读：

- [`journey-design.md`](journey-design.md)：主线路线、城市解锁和内容配置入口。
- [`story-rebuild-plan.md`](story-rebuild-plan.md)：新剧情施工流程、AI 美术一致性、资产契约与验收门槛（规划中，非当前实现）。
- [`story-direction-draft.md`](story-direction-draft.md)：新剧情创作方向与首个代表片段草案（待确认）。
- [`design-system.md`](design-system.md)：视觉方向与 DesignSystem 边界。
- [`realtime-voice.md`](realtime-voice.md)：端侧实时语音、低成本模型、生命周期与真机验收门槛。
- [`relationship-system.md`](relationship-system.md)：多维角色关系、好感度计算、时间衰减与校准边界。
- [`relationship-calibration-log.md`](relationship-calibration-log.md)：关系算法的测试—反思—优化记录与下一轮成熟度门槛。
- [`../Backend/README.md`](../Backend/README.md)：后端本地开发。

## 按需部署

`backend/DEPLOYMENT.md` 只记录当前服务器的实际发布入口。备份、集群、长期迁移和合规流程
等尚未启用的设计不提前固化；需要了解演进历史时使用 Git。
