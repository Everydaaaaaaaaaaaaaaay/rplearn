# 已评分作答合同0.1

研究专用，独立于ItemGroup0.1/0.2；不更改历史题组或生产API。题组描述给学习者呈现什么及如何作答；本对象描述来源已经公布的一份作答和评分。双方通过版本化身份关联，不能把作答例当题目的唯一答案。

本版主要处理PDF公布的书面作答，保留原文件页码与源标签。原生文字、手写图像、页面图像、录音分别标明；录音的独立资产/时间段合同尚未实现，不能据支持modality字段声称完成了音频导入。真实题文与作答留私有缓存，本机摘要登记在Registry。

| 对象 | 保留内容 | 必须防止的问题 |
| --- | --- | --- |
| 身份 | 作答版本、任务与材料家族、源任务/脚本标签 | 不同题型、来源或脚本错配；同源材料重复计样本 |
| 来源引用 | 来源/取得记录、PDF页、角色、表示形式 | 缺失、空内容、非解析字节、错误页码、player壳当题干 |
| 题干配套 | paired或not_acquired；正文与必需图表引用 | 未取题干却称配套完整；丢图后保留文字假装可评分 |
| 作答 | 引用、源完整性、原错误保留、转录状态 | 把原生抽取成功当手写全文转录；纠错后当原考生作答 |
| 分数 | task/criterion范围、量尺band或raw_points、上下界、步长和版本 | 任务band冒充章节/总考试成绩；与原分、奖励或CEFR混算 |
| 维度 | published或not_published；显式分数引用或null | 把任务分数复制成四个维度分；从文字评语自行生成数值 |
| rubric | 应用版本与未知原因；当前公开描述表另作参考 | 当前descriptor自动替代历史内部详细评分规范 |
| 审核/权限 | 对应角色的来源证据、未知状态与用途 | 作者自审冒充独立专家/学生；公开样例自动商用准入 |

Schema刻意仅允许`research_only`。每份记录要有至少一个明确任务分数，本版拒绝在单任务对象内加入section/overall分数；需要考试总成绩时，应由另一种对象保留完整试卷和聚合依据。本版也没有自动band与raw_points转换。

`not_published`维度的score_id必须为null；`published`须引用同一criterion的明确分数及来源。校验器检查角色、引用、来源非空/解析元数据、页码范围、摘要与量尺算术，但不能自动证明原文真正公布了这个维度数字，或该数字已正确抄录。来源分数与上下文仍须核读，独立金标准和商用准入始终为false。

`paired`要求正文和必要图表已取得；`not_acquired`允许保存有评分却缺题干的作答，不能作为已配套的评分锚点。手写图像的full_transcription为false，核读图像不能把它自动改成true。完整转录声明要求verified状态；该状态也须另外保存人工或受控转录证据，Schema一致不等于转录正确。

目前三份原创结构样例分别验证任务总分、缺题干、显式维度分与任务分并存；39个损坏反例覆盖总/维度错配、空量尺、非法半分、NaN/无限值、来源角色、缺图、错误转录及虚构审核/权限。真实IELTS导入16份，12份prompt配套、4份缺题干、全部四维未公布；逐个核对源文件大小/SHA、PDF页数、分数页原生Band值并复用页面核读，另拒绝超范围页、零字节元数据、403录音当作答与player壳配PDF页码四种实际来源反例。

运行检查：

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=build/english-benchmark-research-20261012/python-libs /Users/tiantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 Research/GuYouJi-English-Benchmark/Tools/check_scored_performance_contract.py

PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=build/english-benchmark-research-20261012/python-libs /Users/tiantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 Research/GuYouJi-English-Benchmark/Tools/validate_scored_performances.py --check-assets build/english-benchmark-research-20261012/ielts-private-performances/*.json
```

保留的源评分例仍非本产品目标学习者金标准。公开材料的预训练曝光、家族泄漏、评分者一致性、题干配套、图表语义、历史规范和用途许可都需要独立验收。此增量解决表示缺口，不关闭G05/G11/G12或M4。
