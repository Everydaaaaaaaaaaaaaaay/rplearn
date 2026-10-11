# 五年级正式合同交接复核

2026-10-11，Astra逐题确认delivery.proposedQuestions中的36题。采用主审接受的A04解析、B05干扰项、B06第三配对和B15日期四处修订，A18仍为时间介词配对，B11仍为钟点at补全。没有改已审正文、原稿、delivery、正式目录或主代码。

本轮重读原稿、delivery、`content.ts`的questionSchema与`grading.ts`的answerSchema/gradeAnswer。`primary5-formal.astra.json`顶层记录两个输入文件的实算SHA-256；每行question仅保留对应题型合同字段，审阅与来源放在外层。references沿用题目真实PEP来源及印刷/PDF页码；本轮为来源映射，没有新增教材核读声称。

每题standaloneContext、ambiguityReview、optionNotes以及一正一误的完整LearningAnswer均由作者逐题写定。程序只映射字段、校验合同和执行判题，没有由正确答案程序换位制造错误样例。配对错误样例仍包含全部左右成员且不重复；排序错误样例使用全部合法词块，确保实际检验错误语序而非仅触发格式异常。

## 逐题定稿与判题证据

下表简写只便于人审；JSON内每个probe都是完整后端payload，choice/listeningChoice使用kind=choice，completion使用kind=text，不以题型名充当作答kind。

| 题号 | 正确作答 | 完整错误作答的实质 | 定稿复核 |
| --- | --- | --- | --- |
| A01 | b | a未明确两人共有 | mine不解释为必然排他；共同归属条件已在题面。 |
| A02 | c | a是usually散步 | 三句音频信息完整；不推频度次数。 |
| A03 | they/are/read/books | they/read/are/books | 全词块；起首与标点限制保留。 |
| A04 | in | on | 仅说明November/in November，不再讲on/at对照。 |
| A05 | l1-r2/l2-r3/l3-r1 | l1-r3/l2-r2/l3-r1 | 日期与数量互换会改变意义，钟点仍正确。 |
| A06 | my | mine | cup已经给出，独立代词不可再接名词。 |
| A07 | a | b问现在 | 交流目的明确周末习惯。 |
| A08 | b | c听音乐未提 | 以音频动作而非地点或性别判断。 |
| A09 | when/is/trip | when/trip/is | 完整问句而非陈述语序。 |
| A10 | a | b错月日 | 给定日期，无日历推算。 |
| A11 | l1-r2/l2-r3/l3-r1 | l1-r1/l2-r3/l3-r2 | 所有话由Sam说，my/your不能换视角。 |
| A12 | i/often/walk | i/walk/often | 错误违反题内位置约束，不能泛称句末often永远不合语法。 |
| A13 | cleaning | clean | am已给，只填一个分词。 |
| A14 | c | a把July听成June | July尾音待媒体实听，不声称文本校验等于音频验收。 |
| A15 | second | two | 完整英文序数词限制保留，2nd不作为本题合格输入。 |
| A16 | b | a改成his | 保留明确her所指；theirs释义不作性别绝对化。 |
| A17 | c | b不包括自己 | 同时检验现在动作与说话人范围。 |
| A18 | l1-r3/l2-r1/l3-r2 | l1-r2/l2-r1/l3-r3 | 原目标保留，交换星期和月份错误。 |
| B01 | b | a扩大成每次 | 有时不能推每次或具体频次。 |
| B02 | am | is | 第一人称与be搭配；listening已在句中。 |
| B03 | c | a改成说话人 | Sam's与his同指，不能凭声音或姓名猜。 |
| B04 | birthday/is/on/date | birthday/is/date/on | 日期词块完整，on不能放在末尾。 |
| B05 | a | c虚构星期三 | 正确项It is in October保留；b为October 12th，无first/eighth或at钟点提示。 |
| B06 | l1-r2/l2-r3/l3-r1 | l1-r1/l2-r3/l3-r2 | 第三条确认为I am watching TV，不含原reading整句。 |
| B07 | theirs | their | 空后无名词，限定词不能独立作该答案。 |
| B08 | what/do/you/saturday | what/you/do/saturday | you usually do词块不拆，疑问语序正确。 |
| B09 | a | b错日期 | 同时核对March与first，实际音频未验。 |
| B10 | b | a变成习惯 | 明确一个男同学此刻活动；cleaning跨组风险仍由delivery互斥处理。 |
| B11 | at | on | 原钟点介词目标保留，没有December拼写替题。 |
| B12 | whose/is/this | whose/this/is | Whose umbrella完整词块询问主人。 |
| B13 | l1-r2/l2-r1 | l1-r1/l2-r2 | 两项完整错配，不靠缺项制造失败。 |
| B14 | having | haveing | 题中已有are；错项真实检验去e拼写。 |
| B15 | b | a基数eight | 日期为六月八日，eighth是审定答案。 |
| B16 | c | a回答了当前活动 | 选项不带通常/现在标签，脚本独立提供时间。 |
| B17 | a | b的my缺名词 | 肯定本人归属且不重复物品名，保留指令条件。 |
| B18 | what/are/they/doing | what/they/are/doing | 问身边同伴有关那些孩子，they视角不变。 |

实际调用当前后端answerSchema和gradeAnswer，72条probe全部符合预期：36条correct、36条incorrect，没有用缺字段、无效选项ID或重复成员替代完整错误作答。30道非听力question通过完整questionSchema。

6道听力依指示暂不写audio：其余字段通过listeningChoice分支去除audio后的结构检查，同时确认它们尚不能通过完整questionSchema。音频脚本独立存于每行audioScript，未伪造assetId。因此“30题合同完整＋6题待真实audio合同”不能写成36题已可发布。gradeAnswer并不读取audio，故72条判题可先真实执行，但不能证明媒体加载或听辨通过。

## 音频制作计划

`build/learning-primary456-20261011/primary5/production-plan.json`按`Scripts/produce-story-voices.swift`的clips/segments结构写出。六段分别为A02、A08、A14、B03、B09、B16，transcript与segment.text均精确等于审定audioScript，保留全句和标点，不改写台词。每段采用F3、rate 0.78、breath=false；目标100 WPM、制作检查范围75—125 WPM，仅是制作目标，非课标规定。实际语速取决于渲染结果，需生产后测量和实听。

A02需听清三个频度词和活动对应；A08听清drinking water；A14听清July尾音；B03听清Sam's及his；B09听清March first；B16分清usually与now。此处仅为制作验收关注点，不冒称已经听过成品。本代理只写计划，没有运行渲染；由主代理串行生产避免模型争用。

本轮检查输入哈希、逐字段正文相等、来源ID、六脚本一致、题数、完整payload、真实后端判题与diff空白。没有运行UI、生产、儿童试做或教材整册验收，没有提交或部署。后续仍需将delivery有效互斥边转换为正式身份、填入真实音频资源并完成独立发布验收。

正式review合同补核：16道选择／听选的optionNotes已逐项亲写为a/b/c对象，每条至少8字；20道其他题型为{}，原综合审阅原文并入ambiguityReview，未改题目或probe。
