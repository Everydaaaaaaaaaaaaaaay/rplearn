# 高三两道跨题提示替题终修稿

2026-10-11，Astra 逐题亲写终修。状态为**作者自审完成，待主代理终审**。只更新本记录和同名 JSON，未改正式库、未提交、未访问生产。程序只检索、展示和核验已写内容，没有组合或批量生成题目。

## 最终候选

| 原完整位置 | 终修任务 | 保留项 |
| --- | --- | --- |
| `ruby.senior3.coastal-display-captions / q1` | 读游客拍摄被海浪冲上海滩的船，区分后置修饰、另加事件顺序、错接修饰对象。 | q1、原 goal、choice、答案 a。 |
| `ruby.senior3.project-conditions / q3` | 六词块组成 `Given that the hall is too small, we need a larger venue.` | q3、原 goal、arrange、六词块。 |

q1 题干为：`A visitor photographed a boat washed onto the beach by the waves. 哪项符合原句？（washed onto：被水冲到）`。选项依次为：a 游客拍到了一只被海浪冲上海滩的船；b 游客拍下一只船后，海浪才把船冲上海滩；c 游客被海浪冲上海滩时拍下了一只船。相比上版，删去重复追问，不再用“船推动海浪”这种仅凭常识即可排除的弱干扰项。

q3 题干压缩为：`鉴于大厅太小，我们需要更大的场地。（venue：场地）`。指令只保留“用全部词块组成一句话，以Given that开头”。不再把简单组句写成管理员确认、合作邮件、不能假设等多层操作说明。改用大小与需求关系，也避免再次复用同池维修进行时材料。

## 核读证据和目标边界

本轮重新实际读取以下已登记缓存正文：

- `build/learning-all-grades-20260929/research/pep-senior3.pages.json` 一基 PDF 第24页，页尾印刷17页：`Review useful structures` 要求识别过去分词作定语、状语、表语和宾补，再改写有关句子。新 q1 迁移其中定语的被动关系与修饰对象，不声称摄影句取自教材。
- `build/learning-all-grades-20260929/research/fltrp-senior3.pages.json` 一基 PDF 第36页，页尾印刷29页：`Review: adverbial clauses` 分类条件、比较、原因、时间；例 d 的 `Given that` 引出已知理由。新 q3 采用该原因功能，不复制敦煌或博览会例句。

这是提取正文核读，没有目视原页图，也没有重新核实公开存档的版次印次。已核对 catalog：coastal 目标是过去分词被动修饰对象与悬垂修饰；project-conditions 目标是区分条件、让步、原因、目的并保留逻辑范围。新 q3 是此目标内的**有支架原因组句**，Given that 已由词块提供，不能将答对夸大为独立辨认或提取连接词的证据。

## 答案边界与逐题反例

**q1：** 只接受选项 a，不是开放翻译题。b 无依据增加“拍完才冲上岸”的事件顺序；c 把被冲的对象由船变成游客；第三个诊断反例是“visitor 有 photographed 和 washed 两个并列谓语”，它误将后置修饰读成独立并列动作。第三反例仅在作者复核中使用，不增加学生选项。释义支架解释 washed onto 的意思，但未直接指定受事是 boat。

**q3：** 只接受 `t1,t2,t3,t4,t5,t6`。给定起首、逗号、句号且每块恰用一次时没有另一自然顺序。自由改写可将原因从句置后，但须改大小写和标点，不属于给定词块的合法变体。三个错误序列及逐项理由已写入 JSON：①把需要场地放进 Given that 后并让句号打断句子；②互换 the hall/we，使 we is 与 the hall need 都不成立；③将 need 直接接 the hall 并把 we is 留到后面，既失去主谓一致又破坏原因关系。它们检查当前六块的真实边界，不冒称三种独立高阶能力。

## 同池直接答案泄露复核

重新阅读 senior3/projects 六个旧单元36题及 `companion.senior3.paper-boat` 18题，共54题：repair-report-focus、archive-time-viewpoint、coastal-display-captions、project-conditions、interview-summary、exhibition-purpose、paper-boat。覆盖题干、选项、词块、配对材料、提示、解析、答案和录音文字；没有把 daily 的 folded-page 当作当前 projects 候选。程序检索用于复核字符串，不能单凭命中判定可共卷。

- q1 新可见字段不含 `collected` 或 `closed`，q2 的 collect→collected 不能再从 q1 复制；新摄影原句与正确中文释义未见于其余候选。q3 Built、q4 Designed 与新题共享被动及修饰规则，学生仍须识别不同句子的修饰对象，属于正常迁移。
- q3 新可见字段不含 `so that`、`unless` 或 `although`，不再给 q5 的目的连接词与行动＋目的句架。`Given that` 与完整新句不见于其他正式候选。旧 q4 的小房间仍适合是让步，新题大厅太小而需更大场地是原因；两题虽有大小话题，关系不同，不能抄一个连接词或完整答案。旧 q6 的场地关闭也是原因规则复习，但未提供本题词块顺序或 Given that。
- `paper-boat / s3.second.q07` 的录音仍有 `We collected fewer paper cups…`，可提供 coastal q2 的词形。目前 bank 中没有同时包含两者 goal/type 的蓝图，不能冒称这项潜在混卷风险已被删除。未来加混合蓝图要重新审查。
- coastal q6 仍在 matching 中给 `closed`，q5 在前而 matching 在末槽。本次没有验证客户端是否能回改已答题，因此只能保留“可能反向提示”的风险，不能宣告无泄漏。
- exhibition-purpose q3 的 `to be invited` 对 repair-report-focus q5、exhibition-purpose q6 的 `to help` 对本单元 q5 仍是既有潜在/反向关系。本次两题没有扩大这些关系，也没有把两题终修等同整个高三池全部风险清零。

新题均无音频，不需要录音或 assetId。两处旧六题单元的中途角色台词仍未前置，属于独立未完成项。

## 验证与剩余风险

已做 JSON 解析、原 ID/goal/type 对应、答案与选项引用、组句每块一次、每题至少三个作者反例、替换后54题池精确词串检索及 diff 空白检查。两旧单元的题型与插槽数量保持，但未修改正式库、未跑组卷器，也未宣告正式组卷验收通过。

主代理仍须终审内容、执行正式映射后的合同及完整组卷验证。未做手机实机排版、学生试做、教师效度审查或线上行为验收。题干已缩短，但有支架的组句本身难度有限；该限制应如实保留，不以冗长指令制造高三难度。
