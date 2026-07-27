# 文档

文档只补充代码中不容易直接看出的稳定信息。模块 API、依赖和运行行为仍以代码、测试及
构建配置为准。

## 日常开发

- [`../README.md`](../README.md)：启动方式、仓库地图和最少开发约定。
- [`architecture.md`](architecture.md)：客户端与后端的边界、数据流和改动入口。

涉及具体领域时再读：

- [`journey-design.md`](journey-design.md)：主线路线、城市解锁和内容配置入口。
- [`design-system.md`](design-system.md)：视觉方向与 DesignSystem 边界。
- [`../Backend/README.md`](../Backend/README.md)：后端本地开发。

## 按需运维

`backend/` 下只保留上线和运维时需要的部署、备份、告警、安全与数据治理说明。
普通客户端或业务功能开发不要求阅读这些文件。

架构决策记录在 `adr/`。已完成的实施计划、阶段交接和验收清单不继续保留；需要了解演进
历史时使用 Git。
