# 初高中命题首版：24小时交付任务

用户于2026-10-13明确接受以年级定位的首版，并授权启动长期任务。启动：北京时间2026-10-13 20:12；争取交付：2026-10-14 20:12（Asia/Shanghai）。截止时按实际证据报告完成与缺口，时间到不表示完成。

优先初一至高三六年级的阅读、完形、适用语言/语法填空规格、配套锚题、原创生成与作者解题检查。教材版本、学期和进度只作元数据；接受正常差异，收学校期中期末月考/教研统测，排除明确竞赛/奥赛/选拔卷。完整16水平、4备考方向和长期M1—M7仍保留，首版与全库/上线分别验收。

## 当前进展：核心审阅包已形成，扩展与外部验证未完成

累计53个完整配套选定源组、21个原创候选。配套指题面/必要图/参考键范围已核读，不代表源题无错、独立金标准、学生标定或商用准入；同卷多组只有一个卷家族。当前[来源矩阵](source-matrix.json)和[题组观察](source-group-observations.json)是计数/引用入口。

可以从[核心审阅包](ReviewPackage-v0.1.md)开始：六年级各两个选定卷家族，阅读/完形/适用语言形式均有原创和完整参照；[18组种子](seed-anchor-index-v0.1.json)新增162个源作答点的逐项作者理由，[冻结索引](review-index-v0.1.json)绑定19原创/161作答点及实际版本。[流程0.2](GenerationProtocol-v0.2.md)给出双输入/风险排除/修题与复算要求。核心材料准备与全库/商用/独立教师学生验收分开，本长期任务仍未完成。

| 年级 | 当前规格 | 已写并作者核查的原创任务 | 选定源组 | 下一必做 |
| --- | --- | --- | --- | --- |
| 初一 | [0.2](Specifications/grade7-v0.2.md) | [阅读](Generated/grade7-library-v0.1.md)、[完形](Generated/grade7-boxes-cloze-v0.1.md)、[词库形式](Generated/grade7-garden-bank-v0.1.md)、[日历](Generated/grade7-calendar-reading-v0.1.md)、[原形词库](Generated/grade7-reading-bus-bank-v0.1.md) | 7，两卷 | 更多负荷、人物图模式待补 |
| 初二 | [0.2](Specifications/grade8-v0.2.md) | [说明阅读](Generated/grade8-lunch-v0.1.md)、[完形](Generated/grade8-radio-cloze-v0.1.md)、[四选语言](Generated/grade8-language-choice-v0.1.md) | 9，两区卷 | 核心审阅/负荷对照；已补模拟开放形式，学校真卷配套仍缺 |
| 初三 | [0.2](Specifications/grade9-v0.2.md) | [说明阅读](Generated/grade9-book-repair-v0.1.md)、[完形](Generated/grade9-cycle-shop-cloze-v0.1.md)、[一词填空](Generated/grade9-weather-grammar-v0.1.md) | 7，两年份卷 | 核心审阅/负荷对照；更多地区仍缺 |
| 高一 | [0.2](Specifications/grade10-v0.2.md) | [三篇语法](Generated/grade10-grammar-v0.1.md)、[完形](Generated/grade10-theatre-cloze-v0.1.md)、[阅读](Generated/grade10-roof-reading-v0.1.md) | 11，两卷 | 核心审阅/负荷对照；第二卷学校/地区身份仍缺 |
| 高二 | [0.2](Specifications/grade11-v0.2.md) | [10空完形](Generated/grade11-exhibition-cloze-v0.1.md)、[论证阅读](Generated/grade11-commitments-reading-v0.1.md)、[单篇语法](Generated/grade11-archive-grammar-v0.1.md) | 8，两卷 | 核心审阅/负荷对照；15空等更多模式待扩 |
| 高三 | [0.2](Specifications/grade12-v0.2.md) | [四简介阅读](Generated/grade12-archive-v0.1.md)、[论证阅读](Generated/grade12-dashboard-reading-v0.1.md)、[完形](Generated/grade12-bridge-cloze-v0.1.md)、[语法](Generated/grade12-workshop-grammar-v0.1.md) | 11，两卷 | 核心审阅/负荷对照；全年冲刺范围仍缺 |

[初一第二来源对照](Comparisons/grade7-source-comparison-v0.1.md)扩展三选/四选、日历/人物图；[高二第二卷对照](Comparisons/grade11-source-comparison-v0.1.md)扩展10/15空完形、三篇/单篇语法、书评/论证及概念/视角范围。[初二丰台第二来源对照](Comparisons/grade8-source-comparison-v0.1.md)扩展8/10空完形、3/4题阅读和完整单项，保留第20空缺been风险。[初三第二年份对照](Comparisons/grade9-source-comparison-v0.1.md)增加表格行关系、派生名词/物主限定词与共享被动，保留technology…have源一致风险。[高一第二卷](Comparisons/grade10-source-comparison-v0.1.md)与[高三鞍山对照](Comparisons/grade12-source-comparison-v0.1.md)补15空/单篇语法及论证/实验，六年级均已有第二卷。源人名混用、缺词、错印、解析题号错位和措辞风险保留，不悄改原文或当正向范例。

[命题/作者审核流程](GenerationProtocol-v0.1.md)规定规格＋完整匹配锚组双输入、合法响应、逐项依据/干扰项、实际修题再解。候选旁的作者检查JSON保存对应版本摘要/答案；旧候选仍指向原规格，不用新版本覆盖历史证据。[作者检查证据口径](AuthoringEvidence.md)区分拟稿叙述和实际保存前后文本的修订，不编造审核次数。

2026-10-14检查：[19候选/18种子与八个登记拒绝](../Studies/2026-10-14-firstrelease-core-review-package.md)。首版尚待额外图文/语言模式和更广负荷、持续反例复核及必要保存；作者检查不是第三方认可。没有真实CEFR/学生用时/细档阈值。[日历模式扩展](../Studies/2026-10-14-firstrelease-calendar-role-extension.md)及[原形词库](../Studies/2026-10-14-firstrelease-unchanged-bank-extension.md)后最新[索引0.3](review-index-v0.3.json)为21组/174作答点；第21保存仍为原19组基线。

已完成增量记录：[首批13组](../Studies/2026-10-13-firstrelease-selected-grade-anchors.md)、[高三及补组](../Studies/2026-10-13-firstrelease-grade12-and-extra-groups.md)、[三个首轮闭环](../Studies/2026-10-13-firstrelease-three-authoring-loops.md)、[六年级首轮检查](../Studies/2026-10-13-firstrelease-six-grade-draft-check.md)、[第二来源候选边界](../Studies/2026-10-13-firstrelease-comparison-boundaries.md)。这些是各时点记录，最新计数与下一步以上表为准。

## 工作顺序

1. 复用已得真卷、答案、教材与国际样例；检索只补六年级题面/答案缺口。每年级优先2—3完整卷，按实际取得再决定是否扩采；数量是控制工作范围的起点，不是标定充分性阈值。
2. 从完整题组提取文章、问题、干扰项、答案依据和语言负荷特征。同卷/同文/转载按家族去重，教材/样卷/模拟卷身份如实保留。答案来源不明或缺失的题组不能成为已配套评分锚点。
3. 形成六年级×适用题型的可执行规格。每项区分来源观察、暂定工程规则、未知；常见范围与例外并存。没有源统计的比例、长度、词汇阈值不编造。先修精确对齐、教材整册、CEFR和产品细档标定留作后续，不阻碍用户已接受的年级首版。
4. 原创生成至少每年级一个完整题组，覆盖适用核心题型；新材料/情境/问题，参考真实命题结构。每题记录答案依据、唯一性、多解、干扰项、语言/题组完整性及修正，不只自称“审核通过”。模型自审保持作者检查身份，独立专家和学生验证仍未知。
5. 用未参与规格提取的来源题组作对照检查，保留差异；公开试卷不称真正隐藏评测。规格＋匹配锚题共同输入生成流程，形成命题/审核提示与审核结果表。

## 首版验收

| 交付 | 需要的证据 |
| --- | --- |
| 六年级来源矩阵 | 真实取得题面/键、正文年级身份、页码/摘要、卷与题组家族；不足明确标缺 |
| 年级及题型规格 | 可执行要求、典型范围/例外、来源定位、观察/暂定/未知分开 |
| 配套锚题 | 完整共享材料、题干/选项/答案及理由，源键与分析分开；原文私有缓存 |
| 原创生成题组 | 六年级均有候选、答案依据/干扰项和实际作者检查/修改记录 |
| 对照检查与可复算 | 留出来源、偏差、规格版本和机器摘要/引用检查 |
| 用户审阅包 | 清晰列出首版成立范围、缺口与下一步；商用许可/真人标定不假称已通过 |

缺少必需行时只交付部分结果，不用其他年级替补。核心质量边界是完整题组、答案依据、唯一性、合理干扰项与年级正常范围。工作时间重点用于规格、生成及解题审核；不逐篇扩展与语言/答案无关的百科核查，不反复访问失败入口，不用频繁全量快照取代命题交付。保留必要摘要/引用验证，资产保存按实质新增批次合并执行。

持续任务恢复使用现有`lingotrip`自动续办，不新建重复任务。没有实质变化时保持安静，在首版交付、重要错误、需要用户处理的具体依赖或截止检查时通知。未经授权不联系/付费/登录第三方或运行生产评测。资料/商业/训练用途继续分别记录，参考真题结构不自动授权原题复制或AI改写。

[初二开放语言补充](Supplements/grade8-open-language-v0.1.json)核读友果八上**模拟卷**的完整十空篇章/键/解析，[规格](Specifications/grade8-open-language-v0.1.md)保留全一词约束和参考键非穷尽反例；不计核心53选定源组或已施测普通学校锚。详见[取材记录](../Studies/2026-10-14-grade8-open-language-key-boundaries.md)。
