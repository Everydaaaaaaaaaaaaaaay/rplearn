# 高一程度规则误拒：最大范围条件与当前扫描

对当前开放候选核读时，发现高一三篇语法第6也使用one of the…parks并错误排除large/larger。这与初三此前修复的规则同类，不能因初三修了就认为全包已修完。旧题和作者理由保留。

[新候选0.2](../FirstRelease/Generated/grade10-grammar-v0.2.md)改为单数park，明确no other local park covers as much land。由实际最大面积条件支持largest，保留最高级目标；不是仅依赖the或one of。三篇4/3/3不变，正文54/50/49→54/56/49 token。十空全部重解，who/that限定关系变体保留；新增一次真实保存转移，此前实际修订继承而不累加成独立审核。

扫描当前候选中的one of/最高级相关语句：旧高一第6和旧初三第8是同类错误；初二接力one of her shoelaces是名词所属结构，高一阅读one of which是关系结构，不套程度修复。源g10.2024.grammar第12考place复数，给定most significant不是由本空决定程度，不因本修复改变。源第14的程度语境与可用变体另留裁决，不用原创新最大条件倒灌源题。

[作者检查0.2](../FirstRelease/Generated/grade10-grammar-author-check-v0.2.json)绑定当前规格、实际前稿/审计、新正文及完整向量。[索引0.12](../FirstRelease/review-index-v0.12.json)/[检查器0.12](../Tools/validate_firstrelease_v0_12.py)核25/205/53、四SVG、两三篇分配与当前用锚25/205理由，源覆盖签名不变。两份双输入请求仍使用相同现行规格和源目录。

修复方法在写完候选/缓存/Registry/索引后，因误用source-matrix的grades字段停止；接续第一次尝试grade_status也在写入前停止。实际字段是grade_progress，随后单独修正当前指针，原已登记方法和审计不重写，结果保存失败阶段及恢复方式。这个工具执行错误未改变原试卷字节或重复计候选。

这是同作者发现和真实修题，不是独立教师/学生或评分全集认证。当前开放表达仍需具体编辑裁决；长期门槛保持未完成。
