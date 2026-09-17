# 排程候选核查：实现版本、语义与采用门槛

2026-09-16，WF-1.2。算法候选核查完成；尚未选择或接入生产排程。

## 可追溯核查

实际搜索 `FSRS Swift official implementation license`，打开 [维护者组织仓库](https://github.com/open-spaced-repetition/swift-fsrs)，再只读克隆至临时目录核对源码。固定提交：`4fbaf20184d62f82a9f44f343337c61a2c5483e9`，不是浮动 main。

- [MIT 许可](https://github.com/open-spaced-repetition/swift-fsrs/blob/4fbaf20184d62f82a9f44f343337c61a2c5483e9/LICENSE)：Copyright (c) 2023 Ben Smiley，使用/分发须保留版权与许可。尚未将第三方代码复制或加入 App 依赖。
- [默认参数](https://github.com/open-spaced-repetition/swift-fsrs/blob/4fbaf20184d62f82a9f44f343337c61a2c5483e9/Sources/FSRS/Models/FSRSDefaults.swift)：默认 w 为 19 项，版本第五版；显式 21 项 `defaultWv6` 才是第六版。README 的“支持 FSRS-6”不能当成初始化默认版本。
- [FSRSParameters](https://github.com/open-spaced-repetition/swift-fsrs/blob/4fbaf20184d62f82a9f44f343337c61a2c5483e9/Sources/FSRS/Models/FSRSModels.swift) 默认目标留存 0.9，最大间隔 36500 天；这不是为我们产品量身选择的参数。
- 发布页最新 tag 仍为 v5.0.0，main 含后续 v6 代码。若以后采用，必须固定实际提交/版本并显式配置，不能把版本标签、算法版本、参数版本混为一谈。

本机针对性执行：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --package-path /tmp/lingotrip-fsrs-audit-20260916 --filter 'FSRSV6|FSRSDefault|FSRSRollback'`，15 项通过（3 suites）；日志 `/tmp/lingotrip-fsrs-audit-tests.log`。在独立临时包运行，未在 LingoKit 执行 swift build。证明候选代码在本机通过所选自带测试，不证明与我们后端一致或学习有效。

第六版自带固定轨迹（连续 good 后 again 再 good）得到天间隔 `[0,2,11,46,163,498,0,0,2,4,7,12,21]`；0 天为短时学习步骤，并非“无需再学”。这些是测试向量，不是给所有用户推荐的固定日程。

## 方案比较与决定

| 方案 | 可取之处 | 未解决问题 | 当前状态 |
| --- | --- | --- | --- |
| 透明固定阶梯基线 | 便于解释、实现、回放，无模型调用 | 参数仍是假设；无法据此保证长期留存或最佳负担 | 可作离线对照，不先公开成科学个性化算法 |
| 显式 v6 FSRS | 有维护者实现、许可与测试；可离线运行 | 跨语言一致性、撤销重评语义、负担限制、参数评估 | 优先候选，暂不加入依赖 |
| 每次请求 LLM 安排 | 可以产生自然语言建议 | 不稳定、不可重算、额外支出，没有必要 | 放弃作为核心排程方式 |

三档“忘记/模糊/记得”是原始自评，不直接映射 Again/Hard/Good：模糊可能部分忘记，也可能完全正确但费力。保留原始评分；候选 UI 可比较“没想起/费力想起/顺利想起”，或保留模糊并采用保守重学，但后者可能增加负担。需要真人理解验证，不能悄悄改成 Hard。

## 下一实施门槛

1. 选定按钮语义后固定映射、内容版本、算法版本、参数及随机种子；同输入多端输出一致。
2. 撤销重评必须从原状态重算，保留曝光事实，不把纠正按钮当独立复习推进多次间隔。
3. 对新词、同日重复、提前/延迟、连续遗忘、离线乱序、时区变化和极端输入跑基线与候选；比较负担和数值安全性。没有真实数据时仅报告合成行为。
4. 先有可靠学习事件与可用性验证，再评估留存。长期效果未到观察期不能宣称优于当前产品。
5. 正常排程不请求 AI；不默默新增用户积分消耗。后端依旧权威，离线结果只是可重算投影。
