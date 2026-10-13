# ICLE500 原始发布与转换损失

2026-10-13。取得原机构 [V1.2 发布](https://dataverse.uclouvain.be/dataset.xhtml?persistentId=doi:10.14428/DVN/RIOSSC)的公开 API、500 篇作文、CSV/XLSX 原件、两份平台 TSV、两份 PDF 和 readme。500 篇原文逐份通过原机构 MD5/字节数与本地 SHA256 校验；这不代表全篇语义复核。原文件在 ignored 缓存，Git 只保存原创分析和元数据。

## 不按转换版标签决定权限

当前原机构 `termsOfUse` 是 CC-BY-NC，未提供版本对象。[UniversalCEFR 转换卡](https://huggingface.co/datasets/UniversalCEFR/icle500_en)正文和 frontmatter 写非商用，495 行的字段却全部写 CC0；其 [资料目录](https://github.com/UniversalCEFR/universalcefr-data-directory)也写 CC0。不能挑选最宽松字段作为授权。各商用、训练、改写、传输与再分发用途均未准入，详见 [权限观察](../Rights/icle500-conflicting-license-observations.json)。没有运行训练或外部模型评测。

## 500、495 和 493 是不同口径

原始 CSV 与 XLSX 各 500 个唯一 ID，等级一致；137 个数值单元的严格十进制差异最大为 1e-15，记录而不改原件。默认 TSV 解析器使五行列数错误，明确反斜杠转义后 500 行八列及等级均恢复；完整文本还须独立核对，不能将列数检查当作内容保证。

转换版仅 495 行。缺五个 ID 与 TSV 的五个问题 ID 不同；它们对应原机构五份带 `_relabelled` 后缀的文件。只登记同词干的候选关联，不猜测重命名原因。495 份现有等级一致；56 份文本完全一致、439 份仅空白规范化差异。缺失原因仍无转换过程证明。

原始等级含七个 NA，不能强填。技术报告排除七篇后剩 493，但其 PDF 页 18 分布与 CSV 的 493 个有效等级不一致，保留两份来源口径，不能移标签凑数。详见 [原始观察](../Datasets/icle500-native-observations.json)。

## 对入口模型的实际价值

元数据 PDF 两页及技术报告九个选页实际渲染核读。报告提供 28 名受训评分者、连通评分与多面 Rasch 的方法依据；其 Rasch kappa 的参照不同于普通 kappa，不能仅见负值就宣告无效。没有重现原始评分模型。作文表现等级不能转换成阅读题难度、国内年级或产品档位。

它可作为受限候选资料帮助研究评分边界，当前不进入商用或隐藏金标准。还需解决权限、分布差异、五个文件关联和本项目人群效度。新增来源不关闭任何必需缺口。
