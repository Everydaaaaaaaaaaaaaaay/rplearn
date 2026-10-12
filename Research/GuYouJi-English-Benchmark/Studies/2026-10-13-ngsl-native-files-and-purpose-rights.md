# NGSL实际词表、频率口径与用途边界

本批取得四个项目页、11份核心/口语/儿童/分级阅读词表、3份版本说明，以及一个扩展频率工作簿。另核读项目FAQ、研究索引、CC BY-SA 4.0正文和Oxford API两套条款。原文件、词形索引及完整网页正文留私有缓存；Git只保存方法、计数和自写观察。见[词表观察](../Vocabulary/ngsl-native-observations.json)、[NGSL用途观察](../Rights/ngsl-bysa-usage-observations.json)和[Oxford API用途观察](../Rights/oxford-api-purpose-observations.json)。

## 实际文件与命题约束

| 来源 | 实际词头行 | 核读结果 |
| --- | ---: | --- |
| NGSL 1.2统计/教学/研究 | 各2809 | 三份词头的大小写折叠成员一致，词形内容不相同 |
| NGSL补充表 | 52 | 独立列星期、月份和数词；与核心有march/may同形交集 |
| NGSL-S 1.2统计/教学/研究 | 各721 | 统计行序不是Rank；TRUE的三个统计字段为未知 |
| NDL 1.1统计/教学/研究 | 各874 | 统计以词头字母序排列，Rank使用带句点的数字 |
| NGSL-GR 1.0 | 5050 | 列名为WordID/Word，没有逐词band列 |

[核心页](https://www.newgeneralservicelist.com/new-general-service-list)标1.2于2023年4月发布，补充表与核心另存，不能将未列在核心文件的月份/数词判为高难词。源文件并未提供逐义项或中国课程等级。march/may的大小写折叠交集只是同形匹配，不证明月份与动词/情态意义相同。

核心教学文件有8509个大小写折叠词形，研究文件有10121个；五组共享形式found、left、mine、rose、wound对应不同词头。研究文件说明按字符串及可能屈折形式分析，不区分意义；例如finded等源字符串不成为学生应学的合法表达。也不能把10121称为学生须掌握的单词数。

实际逐词形对照发现，研究形式不是教学形式的必然超集：核心11个词头、口语545个词头、NDL 4个词头各有教学文件包含而研究文件不含的形式。[口语文件](https://www.newgeneralservicelist.com/ngsl-spoken)的研究a行没有an，I行没有me；教学find行没有found，NDL研究leave行没有left。这里保留来源差异，不自动补词或将“研究”标为更权威。先定义分析目的，再审查选用的词形版本。

口语研究表是721行×17字段的矩形文件，有10024个空字段；原行全部保留，只在显式允许的该文件中将空字段计为填充，不能算作词形。口语统计表TRUE行的Rank/SFI/U均为`#N/A`，720个数值Rank中缺337。不得从行号或缺失排名把TRUE填成337，大小写也不能静默改写。没有频率值仍可保存来源词头成员，按排名截取的操作则必须处理未知。

[NDL页面](https://www.newgeneralservicelist.com/new-dolch-list)标1.1于2023-02-15更新、874词头；旧正文残留875、工具标题残留1.0。下载说明另引用2024和旧.org网址，当前FAQ明确.com为唯一官方站。保留这些不同日期字段，不按链接或引用年猜发布日，也不跟随已失去项目所有权的旧域名。

[GR页面](https://www.newgeneralservicelist.com/ngsl-graded-reader)宣称5000词及11个分档，正文署名年份2024而推荐引用年份2013。实际文件5050个唯一词头，WordID连续1–5050，前50行先列若干月份/数词，再从the开始。与核心相比缺found，与补充表相比缺quintillion。没有明确说明这50行是否从band计数排除，不能为了凑5000删除它们，不能按WordID直接生成11档。即使取得明确band规则，它也不是CEFR、中国年级或产品排位等级。

扩展工作簿原生核读使用openpyxl 3.1.5、保留原值、不执行公式。工作表声明max_row=80830，实际只有31241非空行，其中31240数据行；没有公式。Wordlist字段标2809行NGSL、47行Sup、955行NAWL、27429行未标组。criteria两行重复，使2809行核心只有2808个不同词头；与当前核心CSV相比缺primarily，found的WL_SFI_Rank为2800而当前CSV为2807。它不能默默代替当前1.2统计表。47行Sup也不等于52条补充表：若干词未标Sup，另有zero。工作簿中的Coverage/Cumulative Coverage属于来源语料和计数过程，不是本产品的词汇覆盖或学生理解率。

## 可商用资料与实际许可

四个命名词表页明确标CC BY-SA 4.0。[官方deed](https://creativecommons.org/licenses/by-sa/4.0/deed.en)允许商业复制、改编；[法律正文](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)第3节要求保留署名/通知/来源链接、注明修改，分享改编材料时采用规定的兼容许可，第2与第4节另涉及下游限制及适用的数据库权利。

核心许可署名列Browne、Culligan和Phillips，网页推荐引用却只列前两人；实际署名应保留许可所列各方，不能只复制简化的推荐书目。另三表列Browne与Culligan。计划可先将经复核的开放词表用于有署名的本地频率检查，但本批没有部署。具体分享的索引/数据库/题目是否构成改编材料、如何满足相同方式分享及模型提供商的留存/再许可条件，需按组件和用途记录。不能一概声称CC禁止AI，也不能声称所有模型和输出用途已核权。

命名词表的许可不自动覆盖来源语料文章、链接的字典释义、YouTube片段、独立分析工具或研究论文。扩展31k文件含其他词表和未标组材料，全文件的具体许可范围尚未成立，保留在研究层。项目研究索引只提供文献线索，不是系统综述，也不证明中国学生或本产品的学习效果。旧OGTE停止正常工作/更新的声明已记录，未将它列为可直接接入的工具。

Oxford的[API条款页](https://developer.oxforddictionaries.com/api-terms-and-conditions?tab=commercial)同时含非商用研究与商用两套正文，不能仅凭query tab选择合同范围。商用第4.1–4.2节的授权受后续条件限制；第6.1节限制自动系统复制及与AI的提示、训练、微调、grounding、开发或运行组合使用，仅允许展示格式的用户会话缓存，本地保存须另议Enterprise，第7.4节的非商用TDM也有司法辖区及用途条件。因此“购买普通API即可获得AI命题/训练许可”不成立。未注册、调用API、购买或联系权利人。API、已有词表PDF与OLD网站是不同资源，不能反向用API条款替代全部词表许可核验。

## 核验与下一步

[解析工具](../Tools/inspect_ngsl_files.py)固定来源SHA、字段标题、记录数和指定宽度，保留原字段/记录位置、空字段、未知Rank及词形歧义。11文件共18314来源行不是独立词汇总量。真实输入检查通过，摘要、标题、记录数、空词头及字段宽度五类损坏反例被拒绝。这个结果验证解析边界，未构成逐词独立语言复核。

四次访问失败同时登记：译林当前门户HTTP403、电子教材入口TLS超时，以及候选七上教案PDF/首页TLS超时；候选教案主持机构身份仍未知，没有正文，不能升级为官方教研依据。

下一步把词形参考与实际教材义项/语境分开对照，继续外研/译林版本和完整国内题组配套；保留频率未知与版本冲突，不能以单一词表硬判超纲。G07/G09及所有最终门槛仍开放。最新文件须纳入后续保存与真实恢复检查。

复算命令（输出位于私有研究缓存）：

```sh
PYTHONDONTWRITEBYTECODE=1 python3 Research/GuYouJi-English-Benchmark/Tools/inspect_ngsl_files.py \
  --manifest build/english-benchmark-research-20261012/ngsl-native-inspection-input.json \
  --source-root build/english-benchmark-research-20261012/raw \
  --private-output build/english-benchmark-research-20261012/ngsl-private-native-index.json \
  --summary-output build/english-benchmark-research-20261012/ngsl-native-inspection-summary.json
```
