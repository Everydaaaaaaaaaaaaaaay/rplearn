# Oxford候选词汇索引与来源冲突

已取得的官方分级PDF分别为12页Oxford 3000和8页Oxford 5000增补列表。本批逐页查看版面、等级切换和选定条目，建立原行号/PDF页/原文/词性表达/等级的私有候选索引。20页均有原生抽取和PNG摘要，尚未逐词取得独立复核、全部义项或商用权利。见[观察登记](../Vocabulary/oxford-private-index-observations.json)。

## 计数与解析

| 来源 | 原生候选条目行 | 展开词性/等级行 | 精确显示词头数 |
| --- | --- | --- | --- |
| 3000 | 3313 | 3815 | 3003 |
| 5000增补 | 2015 | 2138 | 1999 |

这些是给定文件和口径的复算统计。列表标题、词头、义项、词族、词性条目与文本中的运行词不等价；不能强行删补行凑成3000/2000，也不能把两表的条目数相加称作学生掌握5000词。大小写折叠会合并May/may及IT/it，故索引保留原大小写。

六处原生断行由已查看图像支持的显式修复处理：两处换行的词性表达、两处词头/词性分离、两处词头内部断开。保留原行、连接方法、理由、证据PNG摘要；没有匹配或匹配不唯一就拒绝。另发现PDF对per cent采用noun.标签；保留这个源标签，不把它误吞进词头。未知行阻止候选索引通过，不能静默跳过。

[解析工具](../Tools/inspect_oxford_pdfs.py)固定两份源文件摘要，保留多词单位、括号提示和数字标记，不自动词形还原、展开别名或推断义项。[边界检查](../Tools/check_oxford_pdf_inspection.py)核验16个选定真实锚点，拒绝5类损坏输入，并确认缺修复会留下阻塞状态。结构成功不是完整语义金标准。

## 冲突必须保留

| 条目 | 已查看PDF记录 | 另一记录 | 当前处理 |
| --- | --- | --- | --- |
| audio形容词 | 3000第4页A2 | 增补第1页B2 | 保留两项，待裁决 |
| well-being名词 | 3000第12页B2 | 增补第8页C1 | 保留两项，待裁决 |
| gender名词 | 3000第11页B2 | 增补第2页B2 | 同条目重复成员，不多算独立词 |
| alongside介词 | 增补第1页B2 | 当前网页C1 | 版本/范围原因未查明 |
| diplomatic | 增补第5页印n./C1 | 当前网页为形容词/C1 | 保存印刷标签，禁止静默修正 |

[当前官方网页](https://www.oxfordlearnersdictionaries.com/wordlists/oxford3000-5000)已核查最后两项。此前2026-10-12 HTML快照的5975行与两份PDF做候选对照；为寻找候选而移除括号/数字标记、规范大小写/撇号/TM及合并词性子类，不代表义项相同。3000的4个等级差异候选中包含银行/河岸等义项混淆，不能把差异一概归为来源错误；增补的15个等级差异和84个未匹配也仍需分别核读。未匹配不是C2、超纲或用户不认识。

[官方方法说明](https://www.oxfordlearnersdictionaries.com/about/wordlists/oxford3000-5000)说明列表结合语料频率与学习相关性，并提示核心词的多义、词族和搭配还需要继续学习。它不是中国课标或教材先修列表。最新抓取与此前同页摘要相同，仅作复查，不能增加独立证据数。

## 命题系统接入条件

出题约束必须引用冻结的来源版本和条目/义项身份，不能只保存一个lemma→CEFR字典。遇到范围、词性或等级冲突，返回冲突/未知及证据；在人工裁决前不能据此硬性放行或拒绝。裁决保留原记录、决定、适用义项、复核者及新版本，不覆盖旧题分析。

词汇库还须与课标及具体教材单元、语法功能、目标任务和学生认识范围结合。这里的候选索引未取得商用出版、改编、训练、数据库复用或外部传输的具体权限，不接入生产生成/评分，也不补造课程对齐。

可复算命令（输出须留私有研究存储）：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Research/GuYouJi-English-Benchmark/Tools/inspect_oxford_pdfs.py \
  --oxford3000 build/english-benchmark-research-20261012/raw/oxford3000-pdf.pdf \
  --oxford5000-additional build/english-benchmark-research-20261012/raw/oxford5000-pdf.pdf \
  --repairs build/english-benchmark-research-20261012/oxford-native-explicit-repairs.json \
  --private-output build/english-benchmark-research-20261012/oxford-private-candidate-index.json \
  --summary-output build/english-benchmark-research-20261012/oxford-native-index-summary.json
```

需使用提供pypdf的研究Python运行时。本批登记/缓存/处理摘要检查通过；G09及所有最终验收门槛继续开放。后续补确切版本与义项裁决、商用权限、教材交叉映射和真实题组受控分析。
