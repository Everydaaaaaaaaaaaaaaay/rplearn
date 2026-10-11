# 小四正式合同交接审阅

2026-10-11。Astra 小四独立作者逐题确认36题；本轮只把主审已接受内容映射为后端合同，没有再次改写教学正文。输入为同目录 `primary4.astra.json` 与已提交的 `primary4-delivery.astra.json`，两文件完整SHA-256保存在formal的inputHashes。只新增本审阅、`primary4-formal.astra.json` 及授权目录中的音频计划；没有修改原稿、delivery、正式目录或主代码，没有提交、部署或渲染。

## 映射约定与真实合同

已读当前 `content.ts`、`grading.ts`，并补读 `catalog.ts` 审阅校验。四份已审替题为A08、A17、B07、B15；其余题面、提示、解释、难度理由、选项/词块/配对及答案逐字段保持原稿。全部操作语以delivery为准，包括A17/B16“选词填空，每块一次。”。两道多空的完整acceptedFills由作者分别写定，没有按逐空候选计算组合：A17为s1=can/s2=cannot；B16为s1=is/s2=are。A17的cannot是原词块ID，展示的是can't，不改ID来猜测显示文字。

每行含question、references、standaloneContext、ambiguityReview、optionNotes、probes；7道听力另含audioScript，question暂不写audio。这7条明确是待媒体接入的部分合同，不声称能直接通过完整questionSchema。原作者status、review、taskIntent、sourceRefs、mediaRequirements等不是正式question字段，未塞入strictObject。

正式catalog只允许choice/listeningChoice的optionNotes非空，必须覆盖各选项ID；其他题型必须是空对象。因此16道选择/听选逐项亲写至少8字审阅，另外20题的词块、输入或配对审阅放在ambiguityReview，optionNotes为{}。每道有至少一个完整正确和完整错误LearningAnswer；没有用skip、未知ID、漏块或不完整配对冒充错误样例。A14另验fall及大小写/末尾句号；B14另验完整cannot与两种撇号，共76条。听选使用kind=choice，听序使用kind=arrange，单空使用kind=text，保持实际判题合同。

## 目标与来源核对

实时核对catalog，p4.clock、p4.routines、p4.weather、p4.permission、p4.ownership、p4.clothes、p4.prices、p4.seasons、p4.ability九个目标全部已登记且level为primary4；没有缺目标，不新增goals文件，也没有套用其他年级目标。

references逐题保留所采用已审题的真实sourceId/pages，另亲写alignment。沿用本会话已实际目视的14张缓存页：PEP印刷17/24/27/48/51/58/61，译林18/24/25/32/33/38/39。A17采用已审替题的PEP24，不保留旧试穿题才需要的58页；A10保留原稿引用51页，alignment说明yours对照另在本次实际读过的48页得到支持。B14否定迁移和A14的fall变体没有虚称原页逐字出现。没有新访问未读页或重验PDF哈希。

## 逐题定稿与剩余疑点

表中“无新增内容问题”仅表示本次格式映射未发现需再改正文的问题，不等于独立教师审定、儿童试做、跨题无支架或媒体验收完成。跨题互斥仍以已审delivery及主代理最终登记为准，此文件不另外改互斥决策。

| 题号 | 定稿及完整判题样例 | 疑点与边界 |
| --- | --- | --- |
| A01 | choice：a正确、c错误。 | 无新增内容问题。钟点4:00已给；不从画笔推断美术课日程。 |
| A02 | arrange：i/work/at/period正确；i/at/work/period错误。 | 顺序约束保留活动—钟点—时段；错误是违反受控任务，不泛称所有中置时间状语不合语法。 |
| A03 | listeningChoice：b正确、a错误；原脚本保留。 | 未实听六点/八点及两句停顿；媒体接入前不能作为完成听力发布。 |
| A04 | completion：to正确、for错误。 | 候选明确仍需输入，未伪称改为点击式单空；无新增内容问题。 |
| A05 | matching：l1-r2/l2-r1正确；全量反配错误。 | 天气语境限定cool；不使用个人冷暖阈值。两项配对可排除，测量强度有限。 |
| A06 | choice：c正确、a错误。 | 无新增内容问题。雨不推出风；天气问句跨题出现的处理沿用delivery。 |
| A07 | arrange：can/i/out/now正确；i/can/out/now错误。 | 词块标点及中文请求限定顺序，不评户外安全。没有再次改题。 |
| A08 | choice：采用已审he干扰稿；b正确、a错误。 | 无新增内容问题。第三人he错误指人，不靠职业权力判断。 |
| A09 | listeningChoice：c正确、a错误；原脚本含角色标签保留在audioScript。 | 必须Friend和Ben两声部，标签不读但句内呼语Ben照读；Mia不发言。尚未实听姓名所有格。 |
| A10 | completion：mine正确、yours错误。 | 帽子主人明确；仍是键盘输入。引用保留51页，另核读48页支持yours。 |
| A11 | choice：a正确、c错误。 | 无新增内容问题。明确太小，不引入尺码换算或真实试衣图。 |
| A12 | arrange：much/is/scarf正确；scarf/is/much错误。 | 无新增内容问题。单条围巾、三完整词块，不新增总价计算。 |
| A13 | listeningChoice：b正确、a错误。 | 未实听forty/yuan清晰度，不能仅凭脚本判媒体可用。 |
| A14 | completion：autumn、fall、带空白和句号的Autumn正确；spring错误。 | fall为目标接受的变体，不声称译林所读页出现；中文给秋天，不靠野餐猜季节。 |
| A15 | matching：l1-r2/l2-r1正确；全量反配错误。 | 无新增内容问题。问什么与问能否的信息类型不同；不测试真实儿童画画能力。 |
| A16 | arrange：i/can/see/tree正确；i/see/can/tree错误。 | 可见事实题内明示，不依赖不存在的图；提示支架保留原稿。 |
| A17 | cloze：手写完整can/cannot组合；全量反放错误。 | 已采用主审接受的两个相反许可情景，不用被拒open/use稿；两块两空允许排除，需真实界面检查共享词库和逐空反馈。 |
| A18 | audioArrange：dinner/home/homework正确；home/homework/dinner错误。 | 提及顺序与钟点顺序不同，必须保持脚本次序；未实听，也未验证拖排或点击排序界面。 |
| B01 | choice：b正确、a错误。 | 无新增内容问题。给定午饭一点，When问时间、Where问地点。 |
| B02 | matching：l1-r2/l2-r1正确；全量反配错误。 | 只测提醒语义配对，不宣称独立语法产出；无新增正文问题。 |
| B03 | listeningChoice：a正确、b错误。 | 问F3、答M5计划分声；No和warm同一完整话轮，未实听不能确认否定可辨。 |
| B04 | arrange：what/weather/like/there正确；what/like/weather/there错误。 | 固定天气问句、there?末尾，不额外允许改动词块标点的新问法。 |
| B05 | choice：b正确、c错误。 | 场景区分许可与能力；没有在题干英文预告答案，无新增问题。 |
| B06 | arrange：whose/gloves/are/these正确；whose/are/gloves/these错误。 | 以给定词块含these?为准；不改成另一标点版本的Whose are these gloves?，也不把中文一副当英语单数。 |
| B07 | choice：采用已审Ben's干扰稿；c正确、b错误。 | 无新增问题。主人Leo，所有格须保留；Ben's与旧库互斥另由主代理登记。 |
| B08 | listeningChoice：a正确、c错误。 | 尚未实听trousers/too long；脚本没有价格，不加新信息。 |
| B09 | completion：them正确、it错误。 | 操作语限定候选，所以these等自由表达不在范围；保留键盘型输入。 |
| B10 | choice：a正确、c错误。 | 无新增问题。币种及三十元已明示，价格不计算。 |
| B11 | matching：l1-r2/l2-r1正确；全量反配错误。 | 只评对问句的直接回应；并非断言真实购物对话不得附带报价。 |
| B12 | arrange：winter/we/skate正确；we/winter/skate错误。 | 保留In开头限制，冬天滑冰由题面明确，不以活动反推季节。 |
| B13 | listeningChoice：b正确、a错误。 | 未实听summer；春季划船是教材常见搭配，不能替代本题音频事实。 |
| B14 | completion：cannot、can't、can’t正确；can错误。 | 否定为目标内迁移，引用页未声称逐字有cannot；单空仍需拼写。 |
| B15 | choice：采用已审they干扰稿；c正确、b错误。 | 保留我能的能力回答目标，换干扰不等于消除共同人称教学；无新增正文改动。 |
| B16 | cloze：手写完整is/are组合；全量反放错误。 | shorts复数、dress非复数；两块两空允许排除，实际共享词库操作尚待UI验证。 |
| B17 | matching：l1-r2/l2-r1正确；全量反配错误。 | 两个说话场景的中文阅读负担仍需儿童试做；按要求原样保留已审正文。 |
| B18 | choice：b正确、c错误。 | 用户直接向店员问价，未恢复三方代问；无新增内容问题。 |

## 音频制作计划

`build/learning-primary456-20261011/primary4/production-plan.json`已先交主代理。精确复用A03、A09、A13、A18、B03、B08、B13七脚本，7 clips、9 segments。A09的Friend用F3、Ben用M5；B03提问F3、完整回答M5；其他片段F3。每个同一说话人的完整话轮保留，不切词，不按作息时间重排A18。

rate为0.76，目标100 wpm、观察范围75–125 wpm，仅作儿童练习的制作目标，不是课程标准，也不是实测结果。allowLongUtterances显式为true，匹配现有脚本合同；实际语速、过短片段停顿、否定词、名字及币种的可辨度均须渲染后实听。人物标签不朗读，主代理后续制作媒体transcript时须区别带角色原脚本与实际朗读文字；本计划不写假音频assetId。

## 本地验证

使用真实questionSchema逐条校验：29道非听力完整通过；7道听力的唯一合同缺项均为audio，符合本次暂不接资源要求。没有为了通过校验临时构造伪资源。

76条作者手写LearningAnswer均通过answerSchema，送入真实gradeAnswer后与correct标记一致。多空样例都是完整两空，错误例没有重复用词、未知ID或漏空。另校验36题ID一一对应、四个替题之外字段原样、操作语与delivery一致、references sourceId/pages与采用的已审题一致、全部来源在catalog存在、九个goalId已登记及两输入哈希仍匹配。JSON解析及新增文件差异空白检查通过。

以上是离线合同和判题证据。七段音频未实听、两道多空未做界面验收、儿童阅读负担未试做；正式媒体验收、真实资源接入与最终发布仍由主代理继续。本轮没有需擅自改正文的新阻塞问题。
