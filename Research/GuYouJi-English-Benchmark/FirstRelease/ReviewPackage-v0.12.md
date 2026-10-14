# 初高中当前统一审阅包0.12

从[可执行标准0.4](PracticalAuthoringStandard-v0.4.md)选年级/完整模式，再按[组合索引](combined-review-index-v0.3.json)取当前题面、作者理由、源和版本。核心仍冻结[0.14](review-index-v0.14.json)，扩展源/原创另列，旧审阅包0.9和历史稿保留。

| 年级 | 核心源组 | 扩展源组 | 源参考响应 | 父卷身份 | 当前原创材料：核心/补充/扩展 |
| --- | ---: | ---: | ---: | ---: | --- |
| 初一 | 7 | 10 | 96 | 3 | 6 / 0 / 2 |
| 初二 | 9 | 7 | 90 | 3 | 4 / 1 / 2 |
| 初三 | 7 | 10 | 111 | 3 | 3 / 0 / 2 |
| 高一 | 11 | 7 | 115 | 3 | 3 / 0 / 2 |
| 高二 | 8 | 7 | 105 | 3 | 5 / 0 / 0 |
| 高三 | 11 | 7 | 122 | 3 | 4 / 0 / 1 |

共101源题组实例/639参考响应/18父卷身份，见[分层总览0.5](paired-source-overview-v0.5.json)。不是18完整正式卷、独立文章/学生样本、全国年级阈值或许可金标准。原创分核心25材料家族205响应、[初二开放补充1/10](open-language-supplement-candidates-v0.1.json)、[扩展9/31](Expansions/authored-candidate-index-v0.8.json)；合35现行材料家族246响应点，只是分层总和，修订前稿不重复加计，也不是统计独立性。

核心当前用锚25组205源响应都有逐项作者理由，[统一理由0.5](current-used-anchor-rationale-index-v0.5.json)保留12隔离响应，种子0.2保留18解释组；它们的联合32组不是所有101源组都有统一结构理由。新增48扩展组均有各自私有逐项作者核读，其他未使用核心源的统一理由覆盖继续有缺口，不能将目录配键等同独立语义gold。

新源证据与具体规格：

- 初一[西城2025](Expansions/Grade7Xicheng2025Comparison-v0.1.md)/[草案0.3](Specifications/grade7-v0.3.md)：4词库＋6三选不同材料、活动需求匹配、开放给词多词与选做封顶规则。
- 初二[秋期C卷](Expansions/Grade8Changjun2024Comparison-v0.1.md)/[草案0.3](Specifications/grade8-v0.3.md)：三选/四空五选、50人多选458%、读答部分分及15分点制/七档缺口；学校印字未认证。
- 初三[苏州官方](Expansions/Grade9Suzhou2024Comparison-v0.1.md)/[草案0.3](Specifications/grade9-v0.3.md)：完整词短语/示意图、三或四阅读/四选完形、多种词数作用域；原字节WebP而非PNG。
- 高一[温州期中](Expansions/Grade10Wenzhou2025Comparison-v0.1.md)/[草案0.3](Specifications/grade10-v0.3.md)：单篇/三篇并列、段标题空、邮件/续写整体评分，47解析词/67段首冲突与64much候选。
- 高二[春季新卷](Expansions/Grade11Spring2024Comparison-v0.1.md)/[核心0.2](Specifications/grade11-v0.2.md)：15扫描页、7组45，23借用/29频率/54主谓风险；地区仅文件名，不强认证第三地区。
- 高三[全国卷标题转载组件](Expansions/Grade12National2025Comparison-v0.1.md)/[草案0.3](Specifications/grade12-v0.3.md)：图表分母/舍入/五卡、教师观点转变/研究条件/产出段首；听力仅标题、原题号/官方身份未核。

可直接审阅的新增完整原创：高一[五空七选标题空](Expansions/grade10-club-routines-insertion-v0.1.md)与[完整建议邮件/81正例79流畅错位反例](Expansions/grade10-project-advice-email-v0.1.md)，初二[六类多选调查](Expansions/grade8-library-survey-reading-v0.1.md)与[四空五选日记](Expansions/grade8-river-walk-insertion-v0.1.md)，初一[四卡匹配](Expansions/grade7-workshop-matching-v0.1.md)与[四空词库](Expansions/grade7-lost-property-bank-v0.1.md)，初三[六行表格](Expansions/grade9-repair-table-reading-v0.1.md)与[图文五项词库0.2](Expansions/grade9-book-care-bank-v0.2.md)，高三[六类图＋五方案阅读0.2](Expansions/grade12-library-electricity-v0.2.md)。作者全组解答和实际修订次数记录，未制造修改轮次；高三旧SVGdesc泄合计，当前修掉，原比例像素相同不等无障碍信息相同。

输入关系检查按目录执行：[核心协议0.3](GenerationProtocol-v0.3.md)两请求，[初一](Expansions/Grade7GenerationProtocol-v0.1.md)两请求，[初三](Expansions/GenerationProtocol-v0.1.md)两请求，[高三](Expansions/Grade12GraphGenerationProtocol-v0.1.md)一请求，[初二](Expansions/Grade8GenerationProtocol-v0.1.md)两请求，[高一标题](Expansions/Grade10HeadingGenerationProtocol-v0.1.md)与[邮件](Expansions/Grade10WritingGenerationProtocol-v0.1.md)各一份，共十一份。拒绝真实旧泄题及声明破坏属于当前元数据/文件控制，不等生产模型服从或全部英语正确，也不支持所有101源模式。

仍待独立审阅的[核心17项队列](open-response-adjudication-queue-v0.1.json)保留；新增源的much/big/代词/连接/时态候选、推断和评分制度未决见[扩展26项队列](Expansions/source-adjudication-queue-v0.1.json)。18开放变体＋4推断强度＋2编辑冲突＋2产出问题全部pending；不是裁决已完成。开放参考不穷尽，尚不能当生产精确字符串判分全集。所有作者都是本聊天AI，未取得非作者先解后看键、目标学生首答/用时或对应商业许可。

[第28保存](../Studies/2026-10-14-checkpoint28-current-review-and-source-queue-recovery.md)6733文件完整独立COW恢复，纳截至af5e7d04及准备方法、当时33/240/九请求/扩展26队列。此后两高一模式/35/246/本入口在保存边界之外，下一实质批次合并。源资料在私有缓存/本机快照，Git不能恢复原文件。

当前六项交付有具体可审阅材料，但新模式作者闭环、更多负荷/语境词汇、原身份/媒体、独立教师/学生/商用和隐藏模型门槛仍未完成。优先继续独立可推进的工作；未因截止或本包成稿关闭长期任务。

[响应模式分母](ResponseModeCoverage-v0.1.md)按摘要绑定现行候选：21材料144个每题一选项点、6/60开放词形、4/29共享词库、1/3匹配、2/9衔接、1/1整篇邮件。246不是统一字母准确率分母，邮件两作者示例是同一题面且无教师数值分，15分不是15响应；新增暂定零分/计词规则不冒成原邮件政策。
