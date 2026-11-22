# LingoTrip

原生 SwiftUI iOS App + TypeScript/Fastify 后端。

## 找代码

只读任务需要的部分。Swift 依赖看 `Packages/LingoKit/Package.swift`，Xcode target 与资源看 `project.yml`，
后端命令看 `Backend/package.json`，后端功能在 `Backend/src/modules/<module>/`。
领域背景查 `docs/README.md`，命令与预览入口查 `docs/development.md`，都不是开工前必读。
素材从最近的清单或 README 开始。

## 架构边界

- App 组装导航；Feature target 之间不互相 import。
- Swift 依赖在 `Package.swift` 声明。SwiftData 实体留在 PersistenceKit 的 actor 内，跨 actor 和给 UI 只传 `Sendable` DTO。
- 后端路由调用 service，事务归 repository。跨模块经类型或 service 访问，在 `server.ts`、`worker.ts` 或 infrastructure 里组装。
- PostgreSQL 为准，Redis 可丢弃。供应商密钥只留在服务端。
- 保留用户数据和历史迁移，不能靠删库解决故障。

## 生产边界

- 长期规则（2026-11-19）：不在生产环境、生产 API 或生产数据上运行测试、构建、临时验证脚本、创建测试账号或真实模型评测。
  验证一律在本地或独立的非生产环境进行。
- 发布产物先在本地按生产平台交叉编译成完整包。生产侧只做上传，并通过正式部署入口整包切换，附带健康检查和回滚。
- 排查故障时只读查看服务状态、健康检查和日志。
- 长期授权（2026-09-11，2026-11-19 更新范围）：后端改动完成并通过非生产检查后，直接整包切换到生产，无需再问，
  除非用户明确要求推迟。确认激活的版本和健康状态，保留数据与回滚能力。iOS App Store 构建走单独的发布流程。

## 验证：够用即停

长期偏好（2026-11-17）：走最短的有效回路，证据够了就停，不为“保险”追加检查。

| 改动 | 验证 |
| --- | --- |
| 文档 | 看差异，核对链接和命令，不构建 |
| UI、文案、样式、动效、过渡、简单入口 | 一次 `Scripts/preview.sh build <页面>`，在模拟器上简短看受影响页面 |
| Swift 逻辑 | 相关套件 `Scripts/test.sh -only-testing:LingoTripTests/<Suite>` |
| 后端逻辑 | 相关 vitest 文件；类型契约变化加 `pnpm typecheck` |
| 数据库、事务、同步协议 | 在隔离环境运行受影响的集成用例 |

- 不写临时验证测试。新增测试只用于修复缺陷后的回归，或用户明确要求时。
- UI 自动化、多设备、明暗外观、大字号、架构检查只在改动直接涉及（导航结构、手势、布局适配等）或出现实际故障时使用，
  并且只跑相关的那一条。
- 查看页面优先用 Computer Use。没有 Computer Use 时截一张图确认首屏，交互留给用户在模拟器上看，不用 UI 自动化代替。
- 通过后，只在代码再次改动或出现新问题时复查，且只复查受影响的范围。
- Swift 测试用 Xcode 宿主脚本，不在 `Packages/LingoKit` 里运行 `swift build`。本地单测无需反复申请许可。
  数据库测试需要隔离环境；真实模型评测需要任务授权和隔离的非生产后端。
- 照片素材：新增或修改照片按 `docs/activity-scene-visual-acceptance.md` 验收，并保留逐版本记录；
  在已有照片上做小 UI 改动时复用原有证据。裁切、可读性、手势变化或用户报告的问题再扩大检查。
  被拒或未验收的素材不能发布。

## 收尾

- 开工先看 `git status`，保留无关改动。
- 长期要求（2026-09-11）：每完成并验证一个逻辑改动，就自动创建聚焦提交，不必等用户要求。
  只暂存本任务的路径，检查暂存差异，排除生成物、缓存、凭据和本地配置。
- 未经明确许可，不改写提交，不破坏性重置工作区。
- iOS 改动完成后，用 `Scripts/preview.sh` 安装最新构建并留在模拟器上，供用户查看。
- 最终回复简述改动、验证结果，以及仍未提交的无关改动。
