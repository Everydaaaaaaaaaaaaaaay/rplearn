# 高三两道暴露源题人工返修稿

2026-10-07。本记录与同名 JSON 配套，状态为**作者自审完成、主代理主审 pending**。未改正式库、未提交、未访问线上。收到收尾要求后，仅保存已经逐题亲写的两题及核读证据，没有扩大题量或以降低题型要求换取通过。

## 替换范围

| 原完整题目位置 | 新题任务 | 保留项 | 解除的直接冲突 |
| --- | --- | --- | --- |
| `ruby.senior3.coastal-display-captions / q1` | 读 `A visitor photographed a boat washed onto the beach by the waves.`，辨认主句拍摄动作与后置过去分词的修饰对象/施受关系。 | 局部 ID q1、goalId `senior3.coastal-display-captions`、choice 类型、正确选项键 a。 | 原 q1 提前展示 q2 的 `collected`。新题的学生可见字段不含该词；q2 本身不改。 |
| `ruby.senior3.project-conditions / q3` | 用六块组成 `Given that the hall is being repaired, we need another venue.`，把已确认维修作为需要换场地的理由。 | 局部 ID q3、goalId `senior3.project-conditions`、arrange 类型、六词块及完整句。 | 原 q3 提前展示 q5 的 `so that` 和目的句架。新题的学生可见字段不含该短语；q5 本身不改。 |

两题完整正式字段、来源、正确答案、所有在约束内的可接受变体、错误反例均在 JSON 的 `replacements` 内。`originalFullId` 用单元 ID 与局部题 ID 联合定位，不能只按 q1/q3 跨文件替换。

选择改暴露源题而非仅加互斥，是因为当前两个旧六题蓝图的相关槽位没有候选余量。各改一题即保持原 choice/completion/arrange/matching 槽数，不借其他 topic 补位、不减题、不降级题型。这里说明内容层面的最小修复，不宣称已经执行正式组卷验收。

## 真实核读来源

本轮实际读取了：

- `build/learning-all-grades-20260929/research/pep-senior3.pages.json` 一基 PDF 第 24 页，正文页尾为印刷第 17 页。`Review useful structures` 明确要求辨过去分词作定语、状语、表语、宾补，并改写这些结构。新 q1 仅采用过去分词定语的修饰对象与被动关系，没有声称 washed 一词或摄影句来自教材。
- `build/learning-all-grades-20260929/research/fltrp-senior3.pages.json` 一基 PDF 第 36 页，正文页尾为印刷第 29 页。`Review: adverbial clauses` 要求区分条件、比较、原因、时间，例 d 实际用 `Given that` 引出已知背景原因。新 q3 据此迁移原因从句，不从未读来源新增语法机制。

另读当前 catalog 两个 canDo 与 boundaries：前者要求判断过去分词被动修饰对象，后者要求区分条件、让步、原因与目的。两题均在这些范围内。正文提取阅读不等于原页图目视，沿用缓存来源身份，未重新核实版次印次或全国教学进度。

## 作者逐题判断

**新 q1：** 不再让学生从三段形式中找到已经给过词形的短语，而是阅读完整句，区分 visitor 的 photographed 与 boat 后的 washed。a 保留船受海浪作用；b 把船改成推动海浪者；c 把受事改成游客且增加同时关系。三项均提及游客、船和海浪，不能只靠见到一个熟悉名词排除。词义支架只解释 washed onto，不给出它修饰哪一个名词。题目无需记住原角色剧情；尚未做儿童试做。

**新 q3：** 已知大厅维修是换场地的理由，不是为促成某个结果而采取的行动。`Given that` 的来源已实际读到。六块必须组成两个主语各自明确的分句；改变 the hall/we 的位置会破坏施受关系。起首指令、词块内逗号及句末句号限制现有自然顺序，因此只收 `t1,t2,t3,t4,t5,t6`；并不声称一般英语中原因从句不能置于句末。这仍是有支架的句子组织，不被夸大成开放写作或独立语法诊断。

## 同年级同 topic 候选及新暴露检查

本轮亲读 senior3/projects 的六个旧单元共 36 题以及 `companion.senior3.paper-boat` 的 18 题，包含题面、选项/词块/配对材料、提示、解析、答案与录音文字；程序只辅助定位字符串。读到的单元为 repair-report-focus、archive-time-viewpoint、coastal-display-captions、project-conditions、interview-summary、exhibition-purpose、paper-boat。没有把 daily 的 folded-page 借入当前候选池。

- 新 q1 的完整摄影句、中文正确释义与 washed 修饰判断没有在同池其他题中出现。新 q1 没有展示现有 production 目标 `collected`、`closed`。q3/q4 的 Built/Designed 仍是共同过去分词规则学习，不是对摄影句答案的直接复制。
- 新 q3 的 `Given that` 及整句不见于其他正式候选；其维修进行结构和 repair-report-focus 的进行被动是语法规则共享，未给对方 `been repaired`、`to be invited` 等完整生产答案。现有蓝图也没有同时抽这两个旧目标的槽位。
- 原 q2 的 `collected` 仍见于 `companion.senior3.paper-boat / s3.second.q07` 的录音 `We collected fewer paper cups…`。两者同年级同 topic，但当前没有同时提供这两种 goal/type 槽位的蓝图，因此不是当前可共卷的新增冲突。未来增加混合蓝图时必须重新登记，不能说已从整个池里清除了 collected。
- 原 q5 的 `so that` 在移除 project-conditions 旧 q3 后，所读 projects 候选中只在该 q5 自身题面/答案/解析出现。q5 的候选词库本来就有 so that，这是题内支架，不是另一题预先给答案。
- coastal q6 的 `closed` 与 q5 仍有已知反向复现：matching 现为末槽，completion 在前。此次不改；若支持返回修改旧答案或前移 matching，应升级处理。没有宣称该风险永久不存在。
- 新题都没有音频依赖，无须伪造 assetId。正式旧单元故事仍有中途角色台词，这属于主目标的另一个未完成项，本次没有越权改故事。

## 基本检查与未完成事项

保存后检查 JSON 可解析、两条 replacement 映射存在、原 goal/type 和局部 ID 保持、choice 答案引用有效、arrange 覆盖每块一次、六题蓝图题型数不变、学生可见字段移除指定泄漏词、文档 diff 空白检查。此类程序检查只证明结构，不代替人工语言主审。

主代理逐题审核、正式映射后的内容合同检查、当前互斥规则下的完整组卷验证均为 pending。未主审前不得把本稿登记成已获准正式题，也不因需要收尾而撤掉这些边界。
