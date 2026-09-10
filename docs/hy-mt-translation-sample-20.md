# HY-MT1.5-7B 离线翻译：20 条真实词典例句

日期：2026-09-11。选择腾讯 HY-MT1.5-7B 的 MLX 4-bit 版本，在 Apple M4 / 16GB Mac 上运行。该模型专门面向翻译并支持词义上下文，适合本机批量预翻译；这不是所有离线模型的排名评测。

- 官方模型：[tencent/HY-MT1.5-7B](https://huggingface.co/tencent/HY-MT1.5-7B)，已查阅模型说明、上下文翻译模板和官方推荐生成参数。
- 本地权重：[mlx-community/HY-MT1.5-7B-4bit](https://huggingface.co/mlx-community/HY-MT1.5-7B-4bit/tree/806395bf6a0be05660f5b44519152582c7336715)，社区量化版本，revision `806395bf6a0be05660f5b44519152582c7336715`。
- 权重文件 4,221,806,239 字节；SHA-256 `cdca11a1bc66b77472ec72dbd575e10be97e588f6e42b92bd9dfb0973b2057bf`，下载后与仓库 LFS 哈希核对一致。
- 运行时：mlx-lm 0.31.3、mlx 0.32.2、transformers 5.17.0；加载本地路径，启用 Hugging Face / Transformers 离线模式，没有调用翻译 API。
- 参数：temperature 0.7、top_p 0.6、top_k 20、repetition_penalty 1.05、max_tokens 256；各句 seed 为 20260911 + 序号。每句只生成一次，无人工改写或挑选重试结果。
- 取样来自 `App/Resources/learner_dictionary.sqlite`，与 [Apple 测试](apple-translation-sample-20.md) 的 20 条原句及义项完全一致，包含原库短语式例句。
- 本次输入包含原句、目标词、词性和词典已有英文义项，没有提供人工中文参考译文。Apple 那次仅输入原句，因此不是严格控制上下文相同的模型对比，而是评估可实际使用的预翻译流程。
- 权重许可为 [Tencent HY Community License](https://huggingface.co/tencent/HY-MT1.5-7B/blob/397085d46158ad0b437ffd74228499e8c2a35c76/License.txt)，不是 Apache/MIT；第 6(d) 条说明腾讯不主张生成输出的权利。此次仅本地取样评估，未将模型或译文作为正式产品发布。

## 原始译文

| # | 英文原文 | 模型原始译文 |
|---|---|---|
| 1 | I am reading a good book on economics | 我正在读一本关于经济学的好书。 |
| 2 | He missed school for a week | 他缺课了一周。 |
| 3 | dinner and the movies had been fine | 晚餐和看电影这些活动都挺不错的。 |
| 4 | Get your results the next day | 你可以在第二天拿到检测结果。 |
| 5 | can you take me to the main entrance? | 你能带我去正门吗？ |
| 6 | the British ships dropped anchor and waited for orders from London | 英国舰船抛下了锚，等待伦敦方面的指令。 |
| 7 | he paid all his bills by check | 他是用支票支付了所有的账单。 |
| 8 | the Yankees scored 3 runs in the bottom of the 9th | 洋基队在第九局下半得了3分。 |
| 9 | the right bank of a river is the bank on your right side when you are facing downstream | 河流的右岸，是指当你顺流而下时位于你右侧的那岸。 |
| 10 | there was a break in the action when a player was hurt | 当有球员受伤时，比赛被迫中断。 |
| 11 | a ten day's leave to visit his mother | 请十天假去探望他的母亲。 |
| 12 | it sounds good but what's the catch? | 听起来不错，但其中有什么隐含的缺陷或限制吗？ |
| 13 | what make of car is that? | 那是什么牌子的汽车？ |
| 14 | the great minds of the 17th century | 17世纪那些伟大的思想家们 |
| 15 | each child was expected to pay for their keep | 每个孩子都被要求自己承担自己的生活费用。 |
| 16 | he took a turn to the right | 他向右转了一个弯。 |
| 17 | he wasted his pay on drink | 他把工资都花在喝酒上了。 |
| 18 | he has a feel for animals | 他对动物有着敏锐的感知能力。 |
| 19 | it is only meet that she should be seated first | 她理应首先入座。 |
| 20 | she checked several points needing further work | 她检查了几个还需要进一步修改的地方。 |

## 观察与速度

本样本中，catch、keep、make、meet 的多义词处理明显优于先前 Apple 原句直译结果，但还不能无审校地全库发布。第 4 条擅自增加“检测”；第 9 条把“面向下游”表达成“顺流而下”，可能引入移动含义；第 12 条准确但偏解释性、不够口语化；第 17 条弱化了 wasted 的“浪费”态度。第 3、7、15 条也可更简洁自然。

模型加载 6.04 秒；20 句生成合计 30.40 秒，单句中位数 1.41 秒。首句 4.77 秒，其余句子约 1.01–1.95 秒。仅为本次小样本观测，不能直接外推全库吞吐；预译后客户端只读取译文，不承担这些推理延迟。

运行时 tokenizer 加载报告了不识别部分 rope_parameters 扩展键的警告；推理由 MLX hunyuan_v1_dense 实现完成，20 句全部正常返回。没有测试长上下文行为。

## 复现

在独立 Python 环境安装 `mlx-lm==0.31.3`，准备上述固定 revision 的本地权重后运行：

```sh
HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 python Scripts/sample-local-dictionary-translation.py \
  --model-path /absolute/path/to/HY-MT1.5-7B-4bit
```

脚本只读词典，结果写入 `build/verification/hymt-translation-20/output.json`，包含原始提示词、随机种子、逐句耗时和译文。完整取样 20/20 成功，已核对与 Apple 样本的原文一致；未修改 App 路由或正式词典，等待用户决定是否采用。
