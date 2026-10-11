# 初二接入准备人工审阅

2026-10-11。仅新增本报告及 `junior2-delivery.astra.json`，不改候选原稿、正式库、运行时代码；不提交、不部署、不产音频。每段双语正文及36条instruction由本作者逐项人工拟定，程序只负责落盘、计数、字段核验与调用现有身份函数，没有程序组合或槽位替换造题。

## 实际阅读

完整阅读 `AGENTS.md`、`authoring/junior2.astra.json` 的36题（题面、选项/词块、答案、变体、提示、解析、review）及两则中文故事、`junior2-review.md`、`docs/learning-program/astra-junior-review-2026-10-11.md`。阅读 `units/companion.senior1.window-rainbow.json` 的前置beats字段，未套用高一语言难度。

本轮实际读取 `build/learning-all-grades-20260929/research/pep-junior2.pages.json` PDF30、54、78、86页全文，对应印刷19、43、67、75。所读内容为比较及过去对照、计划问答和目标/行动、邀请/义务/可能性、真实未来条件和否定。未本轮目视PDF，未读外研正文，未核验当前版本或整册；原审阅报告的外研/目视记录仅作历史信息，不继承为本轮完成证据。没有复制教材题目。

亲读本地正式初二六单元全部36题：`oliver.junior2.reading-rhythm`、`oliver.junior2.two-reading-spaces`、`ruby.junior2.invitation-replies`、`ruby.junior2.rain-backup`、`marcus.junior2.photo-project-plans`、`marcus.junior2.photo-day-sandwiches`。实际不存在 `bank/` 目录；阅读 `bank.json`、`bank-catalog.ts`、`bank-content.ts`，确认bank清单引用正式单元，身份由真实 `bankIdentity(question)` 计算。当前 `bank-revisions` 无初二修订引用。未查询生产数据库。

## 故事交付

A故事初稿120英文词，主代理复审后118词，B故事118英文词（按空格计数）；每篇三段，各自 `opening.1` 至 `opening.3`，均 `afterQuestion: 0`、`speaker: 旁白`、英文text和对应中文translation。

A保留收集纸片、小册末页受雨损、转向后像远山、留白放叶、压平卷边的事件。主代理把第二段的“撕页”改为“移走湿过的纸片”，避免把桌上尚在摆放的纸片突然写成已经装订的书页。结尾用翻开再保留的动作代替口号。B保留纸风车不转、握杆过紧、拨开折角、短暂转动又停、空花盆和离开时再次微动。没有具名职业或教材人物，不包含题目完整答案句，也不要求记忆故事才能答题。

故事可跳过/回看是交付约束；JSON中的 `skippable` 与 `questionDependency` 是作者说明，不能未经映射直接加入严格正式单元schema。正式交付需采用现有 `beats` 合同，不能把三段插到答题中途。

## 36条操作提示复核

仅输出ID与instruction，不复制或更改题面。下表记录逐题判断，体现提示是操作要求，不是解题答案。

| 题 | 核读后的操作边界 |
| --- | --- |
| A01 | 选择发出邀请的句子，不预告can |
| A02 | 选择速度记录，不能推导整体能力；原供应A15词形已修复，见下文 |
| A03 | 听录音选意思，不在instruction先说条件未确定 |
| A04 | 三项问答各用一次，不把配对答案放到操作提示 |
| A05 | 听回复选安排，题干本身未先透露拒绝原因 |
| A06 | 只填空缺，依题面good给词要求，不提示well |
| A07 | 依所给词补全空缺，不提示do或will |
| A08 | 全部四块，按原题给定开头 |
| A09 | 从题内两个词选择，不提前提示可能性对应词 |
| A10 | 五选四，原题明确一块多余；不要求全部词块 |
| A11 | 全部四块，保留原题If开头要求 |
| A12 | 完整句听写，可重播；不把听写改成填词 |
| A13 | 仅依留言与后来使用事实判断，不能引入only if事实 |
| A14 | 三个独立回复配下一步安排，不简化成确定程度标签 |
| A15 | 只填指定slowly的比较形式，不把slower说成普遍错误 |
| A16 | 按录音选行动，三项均可作为现实准备，不靠常识排除 |
| A17 | 选建议句准确意思，未扩大为should能力测试 |
| A18 | 全部四块按录音排序，没有干扰块 |
| B01 | 综合两条灯光记录，不要求计算或一般物理常识 |
| B02 | 听取未来计划，区别已完成动作 |
| B03 | 同时核对拒绝四点、提议五点后两条件 |
| B04 | 三项英中逐一配对，不能只对动词忽略主语和否定 |
| B05 | 指定常用不规则比较级，避免把任务外形式泛化判错 |
| B06 | 听回复完整含义，确认时间不是离开时刻 |
| B07 | 自然补全，保留What和How many两种接受答案 |
| B08 | 五选四，原题明确一块多余；录音决定with/without |
| B09 | 全部四块，依题干开头和同长度事实组句 |
| B10 | 完整句听写，可重播；不是自由复述 |
| B11 | 依给词要求只填空缺，保留缩写变体 |
| B12 | 全部四块，依题干否定计划组句 |
| B13 | 录音两个变化维度都须符合，不只听faster |
| B14 | 便条顺序是唯一依据，不按拍摄经验推断 |
| B15 | 三段独立对话各用一次，不能拼成一人的前后行程 |
| B16 | 按题内承诺行动，不承诺现实中人绝不会失约 |
| B17 | 全部四块按录音，另一个自然词序不等于本录音 |
| B18 | 只选句子明确的好处，不扩大成零错误保证 |

## 精确互斥与身份证据

机器可读JSON列7个有效题对，分直接答案供应4对与实质同类任务择一3对。A02/A15已由主代理修题解决，另记resolved。每个题对独立 `exclusionGroupId`，不使用全目标共享大组，不做传递闭包。旧库完整bankID均调用仓库真实函数得到；候选尚未正式转换音频字段，不假造候选bankID。

| 组ID（均有j2.astra.前缀） | 题对 | 关键证据 |
| --- | --- | --- |
| might-a09-b06 | A09 / B06 | B06录音与答后解析完整给出might have to，A09只需填might |
| might-a09-b15 | A09 / B15 | B15.right[r1]原样出现I'm not sure. I might have to，提供A09空缺词 |
| might-a09-invitation-q3 | A09 / 正式邀请q3 | 旧题三块I / might / have to work及解析，完整给出候选目标短语 |
| clearly-b17-comparison-q2 | B17 / 正式比较q2 | B17可见词块more clearly就是正式题完整acceptedAnswers |
| plan-types-a04-plans-q6 | A04 / 正式计划q6 | 三项计划疑问词与信息类别配对；共享How/Where方法地点任务 |
| condition-fact-a03-rain-q4 | A03 / 正式条件q4 | 条件安排不等于已确定事实，听觉入口不同仍是同一局部理解任务 |
| quiet-negative-a10-comparison-q6 | A10 / 正式比较q6 | is not as quiet as 同属性近同义关系；重构增加听辨但不称新语法任务 |

完整旧bankID：

- 正式邀请q3：`question.3f43df1c0646c75836403e00c76188a3355ff979f86ff05a319eb4264846655d`
- 正式比较q2：`question.e63bfbdaa3949a1ffe13d09ff98609ca3249185fed7fbed38e4436d76bf749ba`
- 正式计划q6：`question.f1666b7e3709d41e95527ad8fc2edd64c738c0f9a3bc15e87e5d867b473bd3f1`
- 正式条件q4：`question.d8173edd60932900ef4a7b5a1eceee73e840f22e1382a247bb88f855bacabb49`
- 正式比较q6：`question.a0d6bec340fa766c66a8dfa3f0b80a621ea1f24062e5f0cd89c7d6773a1c31ab`

## 已解决的固定A组问题

A02/A15同在固定18题A组，不能只加互斥而仍声称18题可组。建议主代理精确把A02.options[c].text由 `I read more slowly today than yesterday.` 改为 `I read fewer words per minute today than yesterday.`。题内明确今天每分钟词数更多，c反向且唯一排除；a是更快，b是同速，c是更低的每分钟词数，均描述速度，不靠无关话题做干扰。

对应A02.review.distractors建议改为：“b误用同等速度，c将每分钟词数的方向反转；不推导整体阅读能力更好。”原explanation中“c反向比较”仍成立。主代理已将上述选项及distractors说明落实到源稿；本作者复读最新A02全部字段，确认a唯一正确、c保持速度维度且不再包含more slowly。已删除slowly-a02-a15互斥，并增加resolved记录；固定A组仍为18题。本代理没有修改原稿。A09/B06、A09/B15分别跨A/B组，正式池按题对隔离即可；不为消除跨组近邻擅改题。

## 不互斥边界

JSON逐项记录13组边界。A08/B12是肯定/否定计划重构，A04/A12是信息配对/完整问句听写，A15/B17是不同副词的生成/听后重构，A13/B16/B18是逆推、正向承诺、结果范围三种判断。B06与B15虽都给A09供应might have to，但前者确认时间、后者三段交际目的，不互相供应完整作答，不能因共同邻接A09就互斥。

A16/B14经进一步核对不列互斥：A16三个选项都是可行准备行动，必须听出实际录音；B14已经写出行动，要求保留借相机→学习使用的顺序。B14不告诉A16会播放哪段录音，没有消除独立听辨。A16/正式计划q1同样不列互斥：旧题在目标身份、方法、时间间辨类别，候选在三种行动间辨具体内容。摄影词汇和学习相机主题接近不足以建立互斥。

其他边界包括A07否定复数条件与旧库肯定词形、B05 badly/worse与旧库good/better、B07上下文可省略数量问句与旧库可数单位、A05听义务安排与旧库按意愿选择拒绝句、A11条件内部组块与旧库将来主句组块。正式频率单元没有与候选相同完整答案或同一局部任务，程序说明单元只在B07数量表达处邻接；均不泛化互斥。

## 验证与限制

核验JSON可解析、36条映射与源稿ID逐项相同且只含id/instruction、六段beats字段和三个前置ID、英文总词数120/118、7个有效互斥组ID唯一、1个已解决题对、5个完整旧bankID由真实bankIdentity复核且对应单元在bank.json清单中。仅离线文本与结构证据，不代表媒体制作、真人听感、原生端交互、学习者效度或生产发布。现有四目标不扩充，仍非全年课程覆盖。
