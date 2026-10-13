# 初高中命题首版：24小时交付任务

用户于2026-10-13明确接受以年级定位的首版，并授权启动长期任务。启动：北京时间2026-10-13 20:12；争取交付：2026-10-14 20:12（Asia/Shanghai）。截止时按实际证据报告完成与缺口，时间到不表示完成。

优先初一至高三六年级的阅读、完形、适用语言/语法填空规格、配套锚题、原创生成与作者解题检查。教材版本、学期和进度只作元数据；接受正常差异，收学校期中期末月考/教研统测，排除明确竞赛/奥赛/选拔卷。完整16水平、4备考方向和长期M1—M7仍保留，首版与全库/上线分别验收。

## 当前进展：首版未完成

累计31个完整配套选定源组、9个原创候选。配套指题面/必要图/参考键范围已核读，不代表源题无错、独立金标准、学生标定或商用准入；同卷多组只有一个卷家族。当前[来源矩阵](source-matrix.json)和[题组观察](source-group-observations.json)是计数/引用入口。

| 年级 | 当前规格 | 已写并作者核查的原创任务 | 选定源组 | 下一必做 |
| --- | --- | --- | --- | --- |
| 初一 | [0.2](Specifications/grade7-v0.2.md) | [阅读](Generated/grade7-library-v0.1.md)、[完形](Generated/grade7-boxes-cloze-v0.1.md)、[词库形式](Generated/grade7-garden-bank-v0.1.md) | 7，两卷 | 核心审阅/负荷对照；图文与不变形模式缺口保留 |
| 初二 | [0.1](Specifications/grade8-v0.1.md) | [说明阅读](Generated/grade8-lunch-v0.1.md) | 4，一卷 | 完形、语言形式候选及第二完整配套源；音标/给词候选缺键 |
| 初三 | [0.1](Specifications/grade9-v0.1.md) | [说明阅读](Generated/grade9-book-repair-v0.1.md) | 3，一卷 | 完形、一词短文填空、第二源对照 |
| 高一 | [0.1](Specifications/grade10-v0.1.md) | [三篇语法](Generated/grade10-grammar-v0.1.md) | 5，一卷 | 阅读、完形、第二源/复杂输入对照 |
| 高二 | [0.2](Specifications/grade11-v0.2.md) | [10空完形](Generated/grade11-exhibition-cloze-v0.1.md)、[论证阅读](Generated/grade11-commitments-reading-v0.1.md) | 8，两卷 | 语法候选；15空/单篇模式与更多负荷覆盖 |
| 高三 | [0.1](Specifications/grade12-v0.1.md) | [四简介阅读](Generated/grade12-archive-v0.1.md) | 4，一卷 | 15空完形、单篇语法、第二源及复杂阅读对照 |

[初一第二来源对照](Comparisons/grade7-source-comparison-v0.1.md)扩展三选/四选、日历/人物图；[高二第二卷对照](Comparisons/grade11-source-comparison-v0.1.md)扩展10/15空完形、三篇/单篇语法、书评/论证及概念/视角范围。源人名混用、缺词、错印、解析题号错位和措辞风险保留，不悄改原文或当正向范例。

[命题/作者审核流程](GenerationProtocol-v0.1.md)规定规格＋完整匹配锚组双输入、合法响应、逐项依据/干扰项、实际修题再解。候选旁的作者检查JSON保存对应版本摘要/答案；旧候选仍指向原规格，不用新版本覆盖历史证据。[作者检查证据口径](AuthoringEvidence.md)区分拟稿叙述和实际保存前后文本的修订，不编造审核次数。

已完成增量记录：[首批13组](../Studies/2026-10-13-firstrelease-selected-grade-anchors.md)、[高三及补组](../Studies/2026-10-13-firstrelease-grade12-and-extra-groups.md)、[三个首轮闭环](../Studies/2026-10-13-firstrelease-three-authoring-loops.md)、[六年级首轮检查](../Studies/2026-10-13-firstrelease-six-grade-draft-check.md)、[第二来源候选边界](../Studies/2026-10-13-firstrelease-comparison-boundaries.md)。这些是各时点记录，最新计数与下一步以上表为准。

## 工作顺序

当前材料入口：[来源矩阵](source-matrix.json)、[选定题组观察](source-group-observations.json)、[首批核读记录](../Studies/2026-10-13-firstrelease-selected-grade-anchors.md)。均为首版过程记录，未表示规格或生成验证已经完成。

[第二批补组](../Studies/2026-10-13-firstrelease-grade12-and-extra-groups.md)新增初二完形、高一报道/说明与高三配套，累计20选定组。高三源键一处实际印刷错误、另一处两个时态变体分别保留；这些是实际审核后进入规格的约束。

第一条实际闭环：[初一首轮规格](Specifications/grade7-v0.1.md) → [原创阅读候选及逐题作者检查](Generated/grade7-library-v0.1.md) → [摘要/结构与修正记录](Generated/grade7-library-author-check-v0.1.json)。其他年级与更多题型继续补齐；单组作者检查不等于独立或学生验收。

新增[初二规格](Specifications/grade8-v0.1.md)与[阅读候选](Generated/grade8-lunch-v0.1.md)、[高一规格](Specifications/grade10-v0.1.md)与[三篇语法候选](Generated/grade10-grammar-v0.1.md)、[高二规格](Specifications/grade11-v0.1.md)与[完形候选](Generated/grade11-exhibition-cloze-v0.1.md)。[三个闭环记录](../Studies/2026-10-13-firstrelease-three-authoring-loops.md)保留多解、范围和干扰项的实际修正；[命题/审核流程](GenerationProtocol-v0.1.md)用于后续同规格与锚组双输入。仍缺初三/高三首轮生成、适用核心题型和第二来源对照。

最新[六年级草案检查](../Studies/2026-10-13-firstrelease-six-grade-draft-check.md)：补[初三规格](Specifications/grade9-v0.1.md)/[图书修复阅读](Generated/grade9-book-repair-v0.1.md)及[高三规格](Specifications/grade12-v0.1.md)/[四项目阅读](Generated/grade12-archive-v0.1.md)。六年级各有一个作者审核候选，23选定源组；尚需各适用核心题型、第二来源/复杂体裁及审阅包，首版未完成。上一段是前一批状态，最新缺口以本检查为准。

[第二来源边界核读](../Studies/2026-10-13-firstrelease-comparison-boundaries.md)取得初二语境/音标/给词一词填空候选（缺键）及高二卷/键（正文待核），保留隐藏标题署名与可见封面差异、地区未知和语法解析63/64题号错位；未新增配套评分组。

最新[高二第二卷对照](Comparisons/grade11-source-comparison-v0.1.md)核读五完整配套组，累计28组；[高二规格0.2](Specifications/grade11-v0.2.md)新增15空完形/单篇10空语法、书评/论证阅读及视角、概念和解析配对规则。保留旧规格与原候选摘要；其他年级第二来源和核心题型仍待完成。

据0.2新增[高二论证阅读](Generated/grade11-commitments-reading-v0.1.md)，329 token/4题四选，区分工时估计、可见性与责任原因；当前7个原创候选。依据[作者检查证据口径](AuthoringEvidence.md)，区分拟稿取舍与保存后的修改，前稿未存不计可复算修改次数；无需要改动的发现也如实记录。

最新[初一第二来源对照](Comparisons/grade7-source-comparison-v0.1.md)复用常熟历史材料/日历/人物图与键，累计31配套选定组；[初一规格0.2](Specifications/grade7-v0.2.md)并列三选/四选与图文模式。新增[箱子标签完形](Generated/grade7-boxes-cloze-v0.1.md)，220 token/10空三选，实际保存首稿并修正三盒物品范围，当前8个原创候选；仍缺初一词库候选与其他年级核心类型/第二来源。

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
