# 小六正式字段交接审阅

2026-10-11，小六独立 Astra 作者。新增 `primary6-formal.astra.json` 和本记录；另写六段音频的 `build/learning-primary456-20261011/primary6/production-plan.json`。本轮没有改原作者稿、delivery、正式目录、主代码或其他年级，没有提交、部署或声称媒体实听。

实际重读当前原作者稿36题、delivery短指令及3个获主审接受的完整替题，读取当前 `content.ts`、`grading.ts`及`catalog.ts`，据实际 `LearningAnswer` 合同逐题亲写正反例并调用后端判题。教学文案没有程序拼题：程序只将原文字段转成正式命名、保存逐题手写审阅、完整答案组合和样例，并检查结构及判题结果。

仅采纳B07 `ride→rode`、B14 `My friend→is`、B17 `thinner`三处已审替题和最新短instruction。A18仍是`saw/slept`，B18仍是`drank/am going to`。主审在本轮另明确批准A13、B11原题干的“拖入”改为“选词填入”，对应点击交互；除此之外没有改写既有题干、反馈、选项或词块。四道cloze从原prompt中分出原英文passage，将`[1]/[2]`机械映射为`{s1}/{s2}`，中文条件与英文句子保留。

`inputHashes`记录当前原稿及delivery的SHA-256，方便主代理发现后续漂移。`question`仅包含后端schema字段；来源、三个审阅字段、probes及尚无资产的audioScript放在行级。B18次目标在行级`secondaryGoalIds`保留，未塞入严格questionSchema。36题的goalId、B18次目标均已逐项核对catalog，六个目标全部存在，无新增目标或擅自改映射。references使用已有真实sourceId、各题印刷页/PDF页及具体语言对应；沿用本线程已实际重读的教材提取文本，不声称新增目视整册。

## 逐题字段与实际判题复核

下表正误均是实际`gradeAnswer`结果。JSON的probes提供完整`LearningAnswer`对象，含kind和全部所需字段；不是只有正确项字母或残缺配对。表中配对简称`l1→r2`在JSON中对应完整pairs对象。

|题号|本次正式字段与约束|完整正确提交→正确|完整错误提交→错误|
|---|---|---|---|
|A01|蓝绿桌布长度、三个原选项及反馈原样。|choice b|choice a|
|A02|was/were范围与one bench单数保留；acceptedAnswers包含原大小写变体。|text was|text were|
|A03|先买面包后去公园，audioScript单独保存，无虚构audio。|choice b|choice a|
|A04|四原词块；We起句、时间句末。|arrange we/going/fix/tomorrow|arrange we/fix/going/tomorrow|
|A05|三问三答原样；数组对映射为left/right对象。|matching l1→r2,l2→r3,l3→r1|matching l1→r3,l2→r2,l3→r1|
|A06|只描述六岁能力，三个选项不变。|choice a|choice c|
|A07|take→took；统一忽略大小写与末尾标点。|text took|text taked|
|A08|英文heavier听辨，不恢复数字捷径。|choice c|choice a|
|A09|五词块全用，There起句，地点先于时间。|arrange there/were/trees/yard/last|arrange there/trees/were/yard/last|
|A10|明确昨天未骑车，保留过去否定短答。|choice b|choice c|
|A11|They→are不变，不改成词汇原形题。|text are|text is|
|A12|买礼物、吃午饭、回家三配对原样。|matching l1→r2,l2→r3,l3→r1|matching l1→r1,l2→r3,l3→r2|
|A13|原can/couldn't/can't/could共享库；过去否定、现在肯定双槽。|cloze s1→couldnt,s2→can|cloze s1→cant,s2→could|
|A14|两桌无电脑，听力关键no不删。|choice a|choice c|
|A15|big比较级bigger及原解析保留。|text bigger|text biger|
|A16|Did起句，时间末尾；四块全用。|arrange did/you/visit/last|arrange you/did/visit/last|
|A17|询问吃饭时刻，When正确而非地点食物。|choice b|choice a|
|A18|昨天上午看电影、下午睡觉，原双槽过去式保留。|cloze s1→saw,s2→slept|cloze s1→saw,s2→sleep|
|B01|到过泳池但没游泳，原三个回应保留。|choice b|choice a|
|B02|三张同名对象独立卡，保留无颜色配对捷径的版本。|matching l1→r2,l2→r3,l3→r1|matching l1→r3,l2→r2,l3→r1|
|B03|明天九点画画十二点午饭，原台词与三个选项不变。|choice b|choice c|
|B04|didn't后use原形，未改题目明确事实。|text use|text used|
|B05|I起句，七岁年龄块置末，不推断现在能力。|arrange i/could/piano/seven|arrange i/piano/could/seven|
|B06|去年不存在与今年存在分开；现实真句也可答非所问。|choice c|choice a|
|B07|正式采用获审骑车替题，周一写前一天日记，ride→rode。|text rode|text rided|
|B08|中性听力题干、去年不会现在会的脚本不回退。|choice a|choice c|
|B09|计划问句配时刻、地点、携带物品；原短答合法。|matching l1→r2,l2→r3,l3→r1|matching l1→r3,l2→r2,l3→r1|
|B10|书本高度而非厚度，保留short/shorter/taller三项。|choice b|choice a|
|B11|十年前单数library与复数bridges，四be词共享库不变。|cloze s1→was,s2→were|cloze s1→was,s2→are|
|B12|Last Saturday起句，拍照原词块不改。|arrange last/i/photos/lake|arrange last/photos/i/lake|
|B13|清鞋肯定、洗包否定，原完整两句台词不改。|choice c|choice b|
|B14|正式采用My friend明确一位朋友，候选仍am/is/are，答案is。|text is|text am|
|B15|三张唱歌卡仍独立，时间和肯否是唯一配对依据。|matching l1→r2,l2→r3,l3→r1|matching l1→r1,l2→r3,l3→r2|
|B16|日记周日、购买周六、使用周日，原时间推理保留。|choice a|choice c|
|B17|正式采用黄书2厘米、绿书4厘米的thinner替题及黄书起句。|arrange yellow/thinner/than/green|arrange yellow/than/thinner/green|
|B18|昨晚drank与明天am going to双槽，保留次目标。|cloze s1→drank,s2→going|cloze s1→drank,s2→went|

遵循真实`catalog.ts`加载规则，只有choice/listeningChoice的`optionNotes`逐项使用真实option ID且每条不少于8字符。所有其他题型的`optionNotes`必须为`{}`；排序、cloze及配对的逐块审阅已移入`ambiguityReview`，未删除。completion的受控答案和错误原因也在该字段、原解析及probes中保留。

## 四个完整合法多空组合

A13仅接受`[{slotId:s1, tokenId:couldnt}, {slotId:s2, tokenId:can}]`，两项分别表示过去不会、现在会。

A18仅接受`[{slotId:s1, tokenId:saw}, {slotId:s2, tokenId:slept}]`，两个动作共同属于昨天。

B11仅接受`[{slotId:s1, tokenId:was}, {slotId:s2, tokenId:were}]`，同一过去时段分别对应单数图书馆和复数桥。

B18仅接受`[{slotId:s1, tokenId:drank}, {slotId:s2, tokenId:going}]`，第二词块完整文本仍为`am going to`，不是只填going。

这四组均为逐题手写的完整组合，没有从单槽候选做笛卡尔积，没有接受部分填对作为整题正确，也没有转成choice。错误probes仍完整填满两槽且不重复词块，测试的是教学错误而非格式400。A18、B11、B18的错误样例特意保留第一空正确、第二空错误，实际后端均判整题incorrect。

## 实际验证及媒体界限

直接使用当前Backend依赖运行`node --import tsx --input-type=module`，导入真实`questionSchema`、`answerSchema`及`gradeAnswer`。36题共72条完整正误probes均符合预期；所有answerSchema均通过。30道非听力题完整questionSchema通过。

6道听力按任务要求不填写audio：当前正式schema要求该字段，因此这6题完整questionSchema尚不能通过。本轮用对应listeningChoice分支去除必需audio字段后的严格合同检查其余字段，并直接调用真实判题器完成正误样例；没有添加临时假assetId或将题型改成普通choice掩盖缺媒体。实际音频登记后须重新通过完整正式schema及单元验收。

同时核对inputHashes、36个唯一ID、题目目标和次目标在catalog、真实sourceId、原文字段一致性、3个替题字段、4个槽位合同及全部optionNotes。A13/B11词语变更已获本轮主审明确授权；其他原文字段机械拆分后可还原原稿。

六段录音计划先交主代理：A03/A14/B08为F3，A08/B03/B13为M5，rate 0.8，目标105 WPM、制作验收范围85–135 WPM。这些是制作参数，不是课标规定。clips/segments兼容`Scripts/produce-story-voices.swift`，每题保留完整原台词，不截断或改写。未运行合成、未实听、未登记正式资产；串行生产与媒体验收由主代理继续。

复跑脚本已留存于`build/learning-primary456-20261011/validate-formal.mts`。在仓库根目录运行：

```sh
Backend/node_modules/.bin/tsx build/learning-primary456-20261011/validate-formal.mts
```

可追加`primary6`仅检查本级。脚本按真实catalog规则拒绝非选择题非空optionNotes，校验输入哈希、来源、主次目标、审阅字段和完整probes，调用真实answerSchema/gradeAnswer；不会生成教学内容、填假音频或修改文件。本轮三档实际运行全部通过：小四76条、小五72条、小六72条判题样例；各36题。听力仍按明确的缺audio状态报告，不计为完整schema通过。
