# 初高中当前命题审阅包0.8

六年级53个配套选定源组/12卷家族，当前25个原创家族/205作答点，另有初二开放篇章原创补充1家族/10点。修订前后不重复计样本。由[索引0.13](review-index-v0.13.json)进入选定版本；[0.4历史包](ReviewPackage-v0.4.md)、[0.5包](ReviewPackage-v0.5.md)与旧索引保留，不继续使用旧题号误作答案的种子0.1。

| 年级 | 当前核心候选 | 已表达的主要形式 |
| --- | --- | --- |
| 初一 | 6 | 叙事阅读、完形、可变形/原形词库、日历、四图联合 |
| 初二 | 4 | 说明/成长叙事阅读、完形、单项四选；开放填空另列补充 |
| 初三 | 3 | 说明阅读、完形、所有空一词的篇章填空 |
| 高一 | 3 | 阅读、15空完形、三篇4/3/3语法 |
| 高二 | 5 | 阅读、10/15空完形、单篇/三篇3/3/4语法 |
| 高三 | 4 | 四简介/论证阅读、15空完形、单篇语法 |

[实际使用锚理由0.5](current-used-anchor-rationale-index-v0.5.json)已覆盖当前25个匹配源组全部205个源响应，每项有公布参考键、作者依据和干扰项/变体检查。它覆盖当前实际使用集合，不等于其余28源组或全国/全年完整覆盖。统一理由完整门槛已经通过；独立语义gold、教师、学生和生产验收仍未成立。

十二个源响应隔离出正向示范：已有完形词义重叠与高三源风险，新增初一低分辨率人物图、高一set located、高二very…that、declined/avoided及概念/目的范围混称、高三分母/限定结论与题旨竞争。原文和原键不改，不能因为配套完整就照搬错误。其余响应也不自动成为独立金标准。

开放语言重点审阅：初二run/running；初三busy/busiest及限定/连接变体；高中过去式/完成时、被动分词/完成被动分词及让步/并列连接。给词可多词与全组一词的制度须分清。参考列表不穷尽，生产评分前需要独立裁决，不能按一个字符串误拒自然表达。

按[年级规格](README.md)选择完整匹配锚，再执行[双输入流程0.3](GenerationProtocol-v0.3.md)。[六年级实例负荷](LanguageLoadControls-v0.1.md)和[初二两体裁](LanguageLoadGrade8TwoGenres-v0.1.md)区分正文/题干/选项、句法和支架；真实修订有前后稿。均长/词数接近不等于同难度，没有CEFR或学生分钟/细档阈值。

[0.13检查器](../Tools/validate_firstrelease_v0_13.py)加--check-cache核当前25/205、53源绑定、四SVG、两组三篇分配、种子答案值及实际用锚25/205理由。它核字节/角色/关系，不替代教师解题。旧15个题号误作答案已用[种子0.2](seed-anchor-index-v0.2.json)修正，真实旧错误及合法错字母都被拒绝。实际用锚旧18/160部分集合的严格完整检查仍拒绝，不能虚报覆盖。

第24保存恢复了修正种子/统一理由之前的冻结状态；这些后续材料待下一实质批次保存。下一步检查首版六项交付和命题输入/开放裁决任务，并继续其他年级第二来源负荷与完整长期覆盖。教材、16水平/4方向、独立复核/学生用时、商业许可和隐藏模型门槛继续按[长期协议](../Acceptance.md)推进，长期任务未完成。

[初三Weather Notebook0.2](Generated/grade9-weather-grammar-v0.2.md)实际修复自身第8空：旧one of the…days不强制最高级，busy/busier/busiest均可能；新than Monday明确测试busier。旧误拒与前后稿保留，全部十空重解。源理由对应的过强规则也已纠正；[修订记录](../Studies/2026-10-14-grade9-oneof-rule-and-than-repair.md)区分真实改稿和独立教育验证。

[高一三篇语法0.2](Generated/grade10-grammar-v0.2.md)同步修复第6空one of误拒：新增“没有其他本地公园占地同样大”的最大范围条件，保留largest目标；三篇54/56/49 token、十空重解。旧稿50词的第二篇和旧作者表保留，不能继续当现行评分理由。[修复记录](../Studies/2026-10-14-grade10-degree-condition-and-current-sweep.md)说明真实修订与当前范围扫描。

[初二四选0.2](Generated/grade8-language-choice-v0.2.md)实际修复第11范围结构；源高一14的旧程度排除理由在新用锚0.5中更正，原键不改。两份[三篇语法请求0.3](generation-request-three-grammar-v0.3.json)/[十空完形请求0.3](generation-request-quarantined-cloze-v0.3.json)绑定新目录。

[开放响应裁决队列](open-response-adjudication-queue-v0.1.json)列17具体版本/题号/待回填响应与问题，包括高二3/4/9/10、完成被动分词和参考源13/14/19。这是可交接工作，不是已完成独立裁决；未联系第三方。详见[范围修复与裁决记录](../Studies/2026-10-14-degree-range-repairs-and-open-response-queue.md)。

可从[可执行命题标准](PracticalAuthoringStandard-v0.1.md)快速选择六年级模式和七项质量要求；[六项交付检查](DeliveryCheck-v0.1.md)逐项列已准备材料和实际未通过条件。

[第25完整恢复](../Studies/2026-10-14-checkpoint25-current-repairs-and-queue-recovery.md)已纳入现行修题/种子/理由/请求/17项队列，全部6403文件严格COW与独立根SHA通过。恢复不代替语义、学生或商业验收，后来增量需下一批保存。
