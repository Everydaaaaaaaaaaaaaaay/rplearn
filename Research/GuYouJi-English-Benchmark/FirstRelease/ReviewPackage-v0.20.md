# 初高中统一审阅包0.20

先按[可执行标准0.11](PracticalAuthoringStandard-v0.11.md)选择年级和完整作答模式，再从[组合索引0.11](combined-review-index-v0.11.json)取得实际题面、作者理由、规格、来源和摘要。[交付检查0.11](DeliveryCheck-v0.11.md)分别列材料准备与尚未成立的质量证据。本包再纳2026初二两源16/83与8具体风险；旧0.19保留此前源101/639/18与作者43/277的边界。

| 年级 | 已选源组实例 | 源参考响应 | 父卷身份 | 当前原创家族 | 当前作答点 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 初一 | 17 | 96 | 3 | 8 | 48 |
| 初二 | 32 | 173 | 5 | 8 | 50 |
| 初三 | 17 | 111 | 3 | 7 | 41 |
| 高一 | 18 | 115 | 3 | 7 | 40 |
| 高二 | 15 | 105 | 3 | 6 | 54 |
| 高三 | 18 | 122 | 3 | 7 | 44 |

[源总览0.6](paired-source-overview-v0.6.json)现117实例/722参考/20父身份。这些是选定完整题组，不代表20套音频/评分配套齐全的正式卷、全国年级分布或独立样本。原创由[核心0.16](review-index-v0.16.json)25/205、[初二开放补充](open-language-supplement-candidates-v0.1.json)1/10和[扩展0.16](Expansions/authored-candidate-index-v0.16.json)17/62组成，合43家族277响应点。两个新增任务使用既有源，不增加源组计数；同一家族修订稿和同题多份作者示例不重复加计。

每年级核心规格0.2与扩展草案分别在组合索引中；初二当前0.5、其他年级0.3；接受正常教材版本/学期差异并登记，不等精确对齐才取材。新规格不追溯覆盖旧稿的创作过程。头像置于大题答题要求旁，无角色开场故事。

本批可直接审阅：

- [初三五空七选当前0.2](Expansions/grade9-group-plan-heading-insertion-v0.2.md)与[协议](Expansions/Grade9HeadingInsertionProtocol-v0.1.md)：引述内空和标题空，A/D/F/C/E全组配置；真实初稿C3/F4交换相关后补reports/reserved time，正文302→200、共享七项66token不变，35位置作者重解。
- [高一完整续写](Expansions/grade10-exhibition-map-continuation-v0.1.md)与[协议](Expansions/Grade10ContinuationProtocol-v0.1.md)：原创前文291token、两个段首25token，两段共同是一项产出；139/143新增token作者正/反例均未评分，25分五档整体制，部分事实矛盾不能自动当完全无关零分。

其他当前材料逐项见组合索引和[响应索引0.7](response-family-overview-v0.7.json)，包括六年级阅读/完形/适用语言填空、图表/日历/匹配/共享词库、多种衔接、初三读答、高一建议邮件。[响应方式0.7](ResponseModeCoverage-v0.7.md)分为九类：156选择、60开放词形、29词库、3匹配、24衔接、3读答、1邮件、1续写；不能合为字母准确率或真人评分样本量。

[阅读参照卡0.4](MeasuredReadingReferenceCards-v0.4.md)仍是13源/11当前原创阅读实例，未因新增衔接/续写变成13源/13阅读实例；[句分布](SentenceTokenBinObservations-v0.1.md)和[有限单位](Expansions/Grade10FunctionFiniteUnitControls-v0.1.md)也保留原范围。完整材料、题干、选项、段首与作者输出分开计，未知句界不补值；这些描述不能直接定全国年级、CEFR或学生用时。

[核心用锚理由0.5](current-used-anchor-rationale-index-v0.5.json)覆盖实际使用25源组/205响应，12风险响应隔离。另64扩展源组有各自私有作者核读；未使用核心部分仍有统一理由缺口。[核心17项](open-response-adjudication-queue-v0.1.json)和[源36项](Expansions/source-adjudication-queue-v0.4.json)均pending。源键/解析不一致须保留原题与观察，不以作者意图、下载或模型自审关闭问题。

组合索引的十四既有请求/检查器保持原摘要，仅验证对应文件和声明关系。两个本批新增模式有题面/作者检查/计量和引用核验，尚无新增生成请求控制或生产模型验证；请求数量仍十四。[词汇语境](../Vocabulary/Grade8ContextAliasAndSenseReference-v0.1.md)、[35B词形与词表证据](Expansions/Grade10UnsupportedStanceReview-v0.1.md)继续将词形、POS、别名、义项和未知分开，不从表级标签推通篇/中国年级。

[第31恢复](../Studies/2026-10-14-checkpoint31-conditional-lexical-and-sentence-profile-recovery.md)覆盖旧41/271和7031文件；本批两新家族、源转录与真实修订及第31自身结果待下一实质保存。Git不恢复私有原件；同机COW恢复不是异机或完整环境重建。

当前确认作者准备材料与统一审阅入口。非作者审题、目标学生首答/用时、对应商用许可、隐藏模型验收及长期16水平/4方向/M1—M7仍未完成，首版准备和产品上线分别报告。下一步按具体缺失模式与证据推进，不因本包成稿或期限到达宣布圆满完成。

新[丰台2026](Expansions/Grade8Fengtai2026Comparison-v0.1.md)七组37与[北师大实验2026](Expansions/Grade8BNU2026Comparison-v0.1.md)九组46共16/83；后者必做7/39与选做2/7分开。当前源初二32/173/五父身份，其余五年级各三，新增两包都属于北京大区，不造两个新地区。两个目录创建时pending标记是历史状态，本总览0.6明确已经整合。

[初二草案0.5](Specifications/grade8-v0.5.md)补抽象概念/受众/图形功能、替补可能与实际参与、行动＋原因和整句翻译/多词选做。原90分封顶/100考试分钟不映射产品档位或学生实测，8新风险与原28合36；one of的常见结构本身不判错，但不得泛化排他。新来源和草案没有新增原创或请求，作者43/277、十四请求、13源11作者阅读卡保持。

响应索引0.7中的101/639来源数量是创建时上下文；现行来源以本组合0.11和源总览0.6的117/722为准，响应分类和43/277成员未变。两个新原创建于此前0.19，本轮增加来源与规格，不把旧版本数量冒作当前来源。
