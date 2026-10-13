# 初三作者规则误拒与实际比较结构修订

检查源88时，又核回自身Weather Notebook第8空，实际发现旧one of the…days可容纳busy、busier或busiest。旧作者表断言busy/busier不符合，是过强且错误的课堂公式迁移；此前新源理由称自身结构更强也不能解释为唯一锁定最高级。原文、旧作者表和旧缓存不改字节。

写出[当前0.2](../FirstRelease/Generated/grade9-weather-grammar-v0.2.md)：Friday is…than Monday for our club，响应busier。明确比较结构替代未给出程度约束的one of，新目标为比较级而非原拟最高级；模式仍单篇十空、全部一词，其他学生句子不变。十空完整回填，实际本版新增一次保存前后转移，先前第6/10的一次真实修订继承，不把“两候选修订审计”误计成同一题两轮。

正文从169到167 token；[新作者检查](../FirstRelease/Generated/grade9-weather-grammar-author-check-v0.2.json)绑定当前规格0.2、新文本摘要、真实前稿与修复审计。比较级busier与than配合，busy/busiest不能照旧保留；more busy为两词不合本组一词。没有声称所有开放表达已穷尽或教师/学生验证成立。

[实际用锚理由0.4](../FirstRelease/current-used-anchor-rationale-index-v0.4.json)只纠正源88作者分析中的one of规则，源原busiest/候选busy和所有25组205源响应、12隔离记录保留。覆盖引用改为冻结参考版本＋真实用锚签名，签名包含家族/年级/核心形式/源ID/题量，不把正文改稿当源家族变更；当前候选字节仍由主索引单独绑定。避免理由索引和主索引循环摘要，也不会让换源悄悄通过。

[索引0.11](../FirstRelease/review-index-v0.11.json)/[检查器0.11](../Tools/validate_firstrelease_v0_11.py)验证25核心/205点/53源组、实际用锚25/205、四图/两三篇分配与答案值。将新稿的源改成2025初三语法的实际破坏同时触发用锚关系拒绝。六新增证据/方法/结果的SHA、本地链接和Registry通过；实际修订和错误更正不是独立gold，长期门槛保持未完成。
