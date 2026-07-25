# LingoTrip

LingoTrip 是一款原生 SwiftUI 英语学习 App。用户以旅行世界为叙事框架，与不同城市的 AI 角色聊天、学习词汇、完成剧情，并收集机票与票根。

## 开始开发

前置环境：macOS、Xcode、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
Scripts/build.sh
Scripts/test.sh
```

两个脚本都会先用 `project.yml` 重新生成 `LingoTrip.xcodeproj`。工程文件与 `build/` 均为本地产物，不提交到 Git。

不要在 `Packages/LingoKit` 内直接运行 `swift build`；项目测试需要 App 宿主，并由 `LingoTripTests` 统一执行。

## 工程地图

```text
App/                              App 生命周期、组合根与随包资源
Packages/LingoKit/
  Package.swift                   Module 与直接依赖的唯一清单
  Sources/<TargetName>/           业务实现
  Tests/<TargetName>Tests/        由 App 托管的 Swift Testing 测试
Scripts/                          构建与测试入口
tools/                            离线数据预处理工具
docs/                             当前说明、设计记录与历史计划
project.yml                       Xcode 工程的唯一事实源
```

依赖方向：

```text
App
└─ Feature Modules
   └─ DomainKit / StoryEngine
      └─ LLMKit / SpeechKit / DictKit / PersistenceKit
         └─ CoreKit / DesignSystem
```

Feature Module 之间不直接依赖；跨 Feature 导航在 `App/RootView.swift` 的组合根接线。

## 事实源

| 内容 | 文件 |
|---|---|
| 构建 target、签名与 App 依赖 | `project.yml` |
| Swift Module 与直接依赖 | `Packages/LingoKit/Package.swift` |
| 当前功能、架构与开发约定 | `docs/HANDOFF.md` |
| 当前视觉与信息架构 | `docs/ui-redesign-plan.md` |
| 初始产品和技术规划（历史） | `docs/plan.md` |

更多文档说明见 `docs/README.md`。
