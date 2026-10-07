# 高二题间提示：最小人工替题候选

2026-10-07，Astra高二作者。接续高中234题只读审计，亲自写完三题，保存为同目录 `senior2-cross-question-revision.astra.json`。按收尾要求停止扩题；这是可交主代理逐题审阅的隔离候选，不是正式导入或发布批准。没有修改正式题、制媒体、迁移成绩、访问线上或提交。

## 实际资料与范围

本轮目视重读 `build/learning-research-20260926/pep-senior-selective1-archive-p36.png` 与 `pep-senior-selective1-archive-p48.png`，对应catalog来源 `pep.senior.selective1.review2019` 的印刷29、41页。29页实际包含-ing功能、从It开头不定式结构转为-ing主语、重心变化；41页包含-ing宾语／表语、工作内容句架及By后活动。未重新核对PDF哈希、版权页或当前新版，未复制原课文／习题情境。

三题保持原来的goalId与completion类型。依据是既有 `s2.ing-subject` 和 `s2.ing-roles`，没有扩大正式目标。将原来可从前题抄出的单个词形，改成先辨认信息作用、再填写完整受控活动短语；不是将give/check/listen机械换成别的动词。

| 原完整ID | 新题ID | 本题需要独立完成的步骤 | 唯一受控答案 |
| --- | --- | --- | --- |
| marcus.senior2.interview-worktable/job-not-action | s2.cross.r01 | 区分职责和此刻收椅子的动作；把原职责中的to show转换为-ing表语，保留对象与范围。 | showing visitors around the building |
| marcus.senior2.community-project-brief/single-activity-agreement | s2.cross.r02 | 把整项解释活动移到主语位置，保留without条件；不把内部using pictures误当整句主语。 | Explaining the new rule without using pictures |
| companion.senior2.shadow-boats/s2.astra.second.q11 | s2.cross.r03 | 区分没有做的“喊出问题”和实际采用的“写在卡片上”；将实际做法转换为by后的完整-ing短语。 | writing our questions on cards |

完整题面、提示、解析、来源、全部答案边界和四个反例分别写在JSON对应条目。三题都明确要求保留原活动短语的用词与顺序，故不能假装是开放写作。大小写及末尾标点按现有normalization接受；同义改写、代词替换和合法不定式表达不符合这些受控任务的要求，但不会被解析宣称为一般英语错误。

## 候选间提示检查

沿用刚完成的逐题人工核读：高二projects池共60题，涵盖七个旧6题单元和shadow-boats的18题。重新对照三道候选的答案、关键词与教学功能；程序只辅助检索完整答案和各自首词showing／Explaining／writing，60题均未命中。三道候选互相也没有出现另一题完整答案。这是文本证据，不是语义完备性的自动证明。

- r01替掉listening产出后，旧 `ing-functions` 与 `listening-value` 仍可教授相近的活动内容／进行状态规则，却不能给出职责选择或完整showing答案。interview-worktable的两个completion槽可从r01、旧by-checking、r03选择；唯一matching不再直接提示其中的listening答案。
- r02替掉gives产出后，唯一matching `activity-focus` 的gives不再是新题输出。该蓝图两个completion仍能保持不同任务：原比较活动的comparing与完整活动主语改写；新题解析不会给出comparing答案。
- r03替掉checking后，shadow-boats原第4题的Checking不再给第11题完整答案。r03保留“避免行为／方法”的目标意义，不是将check换成新词后继续只测单词变形。
- 三题新答案分别来自职责、整项活动主语、具体方法；仍共享-ing教学规则。这是允许的教学迁移，不声称三题是互不影响的独立诊断。

## 仍待处理的边界

**待主代理逐题审阅。** 尚未执行正式questionSchema加载、正式库替换、人工互斥重映射、回溯组卷验证或学习者试做；这里只做JSON、原ID映射、goal/type保留和答案结构检查，不冒称运行时可发布。

旧 `s2.astra.second.q04` 与旧 `by-checking` 仍有Checking→checking冲突；旧 `reversed-history` 的checking选项也仍会提示旧 `by-checking`。本次三题方案解决两张无解旧6题蓝图的内容缺口，并解除shadow固定第4→第11题冲突；剩余有替代候选的关系仍需主代理保留互斥，不以“写了三题”宣称高二所有提示问题清零。

候选使用新ID。旧bank内容身份、既有成绩和历史版本的保留由主代理实现；本作者不改这些数据。没有附带恢复发布或线上构建操作。
