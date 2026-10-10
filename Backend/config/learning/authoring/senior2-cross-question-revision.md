# 高二题间提示：三题短题终修候选

2026-10-11，接续2026-10-07三题隔离稿。三道题面、答案变体、反例和跨题判断均逐题人工重写；程序仅保存文字、检索答案片段并检查结构。未修改正式units、组卷器、媒体或线上数据，也未提交。本稿仍须主代理逐题终审，不能直接发布。

## 正文来源及难度

本轮实际目视重读两张教材正文图：

- `build/learning-research-20260926/pep-senior-selective1-archive-p36.png`，来源 `pep.senior.selective1.review2019`，印刷29页。该页要求识别-ing功能、将It开头的不定式活动改为-ing主语，并讨论信息重心。
- `build/learning-research-20260926/pep-senior-selective1-archive-p48.png`，同来源印刷41页。该页呈现-ing宾语、表语、Bill’s job句架和介词后的活动。By例句是解释动作含义，并非本题的“避免打断”方法情境；此处方法提取是作者迁移，不能冒称原页原题。

与高二选择性必修一的结构范围吻合；三题定位为基础迁移，不声称高阶综合题。难度来自职责与当前动作区分、整个活动与内部限制区分、否定行为与实际方法区分，不靠生词或长中文说明。来源版本沿用catalog登记，未重新核对原PDF哈希或版权页，不宣称当前新版及统一学期等价。

## 逐题改动及答案边界

### r01：职责与此刻动作

保留 `s2.ing-roles` / `completion`，原ID为 `marcus.senior2.interview-worktable/job-not-action`。

指令：按原文改写，用 show 的 -ing 短语写出职责。

> I am putting chairs away now. My job is to show visitors around the building.
> My job is ____.

答案为 `showing visitors around the building`；同时接收英式 `showing visitors round the building`。去掉responsibility释义、摘要背景及逐词顺序禁令。学习者必须选择职责，再把职责转为活动表语；不能抄现成的putting。

反例逐项判断：`putting chairs away` 是当前动作；`to show visitors around the building` 自然但不符合指定-ing形式；`showing visitors` 缺少参观地点及完整导览含义；原形 `show visitors around the building` 未完成结构转换。其他自由换动词的释义不属于指定show的改写合同。

来源：印刷41页的工作内容表语，辅以29页活动表达改写。跨题判断：`ing-functions` 仍讲职责与进行动作区别，`listening-value` 仍给Listening，但均不能给出showing或本题完整职责；两道新候选亦没有该答案。允许共同规则支架，不计完全独立诊断。

### r02：保留限制的完整活动主语

保留 `s2.ing-subject` / `completion`，原ID为 `marcus.senior2.community-project-brief/single-activity-agreement`。

指令：按原句改写，用 explain 的 -ing 短语作主语，保留限制条件。

> It takes time to explain the new rule without using pictures.
> ____ takes time.

接收 `Explaining the new rule without using pictures` 和 `Explaining the new rule without pictures`。指令不再用中文重复答案的“不使用图片”，也不以原词不增不减排除自然省略using的表达。需要从原句自行识别限制，并连同解释活动放到主语位置。

反例逐项判断：`Explaining the new rule` 丢失限制；`Using pictures` 误提内部活动并改变原意；不定式主语自然但不符合指定-ing形式；`Explaining the new rule by using pictures` 反转不用图片的条件。按原句改写的范围保留the new rule，不扩展成任意同义作文评分。

来源：印刷29页完整-ing主语转换及信息重心；41页支撑介词后活动的结构范围。跨题判断：`activity-focus` 与 `collecting-stories` 可给活动主语规则和takes句架，但不提供Explaining、without pictures或完整答案；`comparing-viewpoints` 也无法直接复制输出。其余两道新题没有本题答案。

### r03：实际方法提取

保留 `s2.ing-roles` / `completion`，原ID为 `companion.senior2.shadow-boats/s2.astra.second.q11`。

指令：按记录改写，用 write 的 -ing 短语补出实际做法。

> We did not call out our questions. We wrote them on cards.
> We avoided interrupting the speaker by ____.

主答案为 `writing them on cards`；人工接收them、our questions、the questions、questions四种指代表达，以及对应自然的write down形式，共11个明确答案。它们逐项列于JSON，没有程序组合答案。将第二句改为them压缩文字，也保留指代理解；输出仍须包含卡片方法细节。

反例逐项判断：`not calling out our questions` 只重复未做的事，未完成指定write的实际方法改写；`wrote them on cards` 在by后保留过去式；`writing our questions` 丢失on cards；`writing down them on cards` 的代词位置错误，正确的 `writing them down on cards` 已接收。

来源：印刷41页介词后的-ing活动；否定行为与肯定方法的提取为原创迁移。跨题判断：`avoid-interrupting` 和 `by-checking` 分别给avoid及by的结构支架，但不给writing、on cards或本题实际方法。shadow-boats的q04 Checking不再给出本题答案；r01/r02亦不给writing。

## 检查范围与发布边界

本轮重读高二projects池七个旧6题单元和shadow-boats的18题，共60题的题面、选项／词块、提示、解析及音频文字稿，并重新对照上述三题。程序辅助检索showing、explaining、writing及完整可接受答案，只负责定位，跨题结论由人工判断。三题共享-ing规则，不宣称没有教学影响。

改动字段：三题各自的 `instruction`、`prompt`、`acceptedAnswers`、`hint`、`explanation`、`difficultyReason` 及 `authorReview`；更新作者方法、正文核读日期、41页证据表述与一条遗留冲突措辞。保留映射ID、goalId、type、normalization及既有引用定位。JSON可解析，原ID映射、goal/type保留、答案唯一性及 `git diff --check` 已检查；没有运行正式questionSchema、组卷或App测试。

尚有两个明确边界：有限字符串答案集不能声称覆盖任意自由释义，主代理应逐题核对该合同；未进行手机实际排版和学习者试做，短题文本验收不等于设备验收。旧q04与by-checking、旧reversed-history与by-checking的checking冲突仍须互斥。主代理须完成正式映射、组卷验证和逐题发布判断；历史成绩及旧bank身份不由本候选改动。
