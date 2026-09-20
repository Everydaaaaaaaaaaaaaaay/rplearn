# 常用 5000 词例句预翻译流水线

> 2026-09-20 更新：下文 9288 条及同义词例句规则属于历史基线。当前导出要求目标词/真实词形匹配（含合法否定缩略成分），优先原创补充与不同义项。前五千词已全部达到每词 2–4 句，共 11,545 条，其中本次补充 3,757 条及共享译文。补充来源与核验见 `../LearnerExamples/README.md`；旧 batch 仅为历史记录，不代表当前展示集合。

这里仅存放离线生成任务、经 LLM 逐句审查的 seed 数据与审计工具；它不参与 App 或后端运行时构建，也不会调用机器翻译。

## 数据口径

- 英汉释义与频率来自随包 ECDICT，结构化义项和例句来自 Princeton WordNet 3.1。
- 与 App 的 `KeywordAnnotator` 保持同一频率定义：`frq`/`bnc` 都有效时取较小值，仅有一个时取该值。
- 按有效频率、`frq`、`bnc`、词头依次排序并固定取前 5000 个。无过滤的前 5000 项经审计全部都是单个英文词头；第 5000 个词为 `compact`，有效频率为 4495。
- 原始 WordNet 数据在这 5000 词下有 26,430 个义项、32,897 条例句，但 App 不会展示全部原始例句。流水线严格复刻 `DictDatabase` 的 `ORDER BY rank, pos LIMIT 12`，再复刻 `DictUsageExamplePolicy` 的“总数最多 4、每词性最多 2、先让每个词性各取一句、再补齐、句子去重”顺序。
- 最终有 3809 个词可展示静态 WordNet 例句，覆盖 6838 个义项、共 9288 条确定性例句。这 9288 条才是预缓存全集；其余原始行不会出现在当前词卡，预翻译不会增加产品命中率。
- 聊天消息传入的 `contextText` 属于动态句子，无法预生成，必须由运行时 cache miss 异步处理；静态 9288 条完成后，常用 5000 词的所有可展示 WordNet 例句都应直接命中。
- `stableSenseId` 精确复用 App 的 `DictSense.id`（`pos-rank-definition`），source/version 精确复用请求中的 `ecdict-wordnet`/`v1`。另一个缓存指纹绑定来源版本、lemma、词性、义项序号、英文定义、例句序号和规范化例句，使词典某一义项变化只会让相关记录失效。
- 9288 条任务的 `stableSenseId` 最长 344 字符，有 130 条超过 128 字符；服务端请求校验至少应允许 512 字符，不能截断，否则缓存键会变化且 130 条永远无法 resolve/import。其余已核查上界为：候选最多 20 个、单个候选最长 15 字符、英文例句最长 177 字符。

## 逐句工作约束

每个完成记录必须同时给出自然的简体中文整句翻译与该义项在语境中的最小中文含义：

1. 优先从 `candidateMeaningsZhHans` 精确选择一个含义，记为 `meaningSelection: candidate`。
2. ECDICT 候选缺失或过粗时，必须依据 WordNet 定义和整句语境准确提炼，记为 `refined` 并说明原因；不能为了“命中候选”选择错误含义。
3. 不得把同词性下的整组释义复制到 `contextualMeaningZhHans`。
4. WordNet 有些例句使用同义词而非 lemma，本流水线仍翻译该义项，但必须在 `selectionNote` 中如实注明。
5. `reviewStatus: llm-reviewed` 只表示记录已经由指定模型逐句语义处理，不冒充人工审校。

## 可恢复执行

从仓库根目录运行：

```bash
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py stats
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py self-test
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py export \
  --completed Tools/Dictionary/ExampleTranslationSeed/batches/0000-mate-bank-display.jsonl \
  --offset 0 --limit 100 --output /tmp/lingotrip-example-jobs-0001.jsonl
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py validate \
  Tools/Dictionary/ExampleTranslationSeed/batches/*.jsonl
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py audit \
  Tools/Dictionary/ExampleTranslationSeed/batches/*.jsonl
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py merge \
  --output Tools/Dictionary/ExampleTranslationSeed/batches/0012-display.jsonl \
  /private/tmp/lingotrip-0012-part-*.jsonl
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py render-import \
  --offset 0 --limit 100 \
  --output /tmp/lingotrip-dictionary-import-0000.json \
  Tools/Dictionary/ExampleTranslationSeed/batches/0000-mate-bank-display.jsonl
```

`export` 会先读取所有已完成键，再按与 App 一致的确定顺序输出尚未完成的分片，并以临时文件 + `fsync` + 原子替换写入。重复执行不会重新派发已完成记录。合并或导入前必须通过 `validate`：它会重新读取只读词典，验证缓存键、全部来源字段、去重、模型/版本以及“整组释义冒充语境义项”等错误。

`validate` 还会拒绝带“语境示例”等标签的英文回显、通用占位义项、残留生成标记，以及两个大分片在相同行号大面积复用同一译文的错位污染。结构校验无法证明翻译质量，因此每个生成分段仍必须逐条处理，并在合并前人工式抽查分段边界与固定间隔样本。

`render-import` 只在所有输入 batch 通过来源与内容校验后，才按 `--offset/--limit` 把其中最多 100 条审计记录裁成服务端 operator-only 导入 payload，与接口限制一致。候选精确命中时，JSONL 必须已经保存并通过校验的 0-based `selectedMeaningIndex`；依据英文定义精炼的新含义不允许携带该字段，不能伪指错误候选。

`manifest.v1.json` 是当前检查点而非完成承诺。每次增加经逐句处理的 batch 后，运行 `audit`，再据实更新 manifest；严禁只增加计数而没有对应 JSONL 记录。
