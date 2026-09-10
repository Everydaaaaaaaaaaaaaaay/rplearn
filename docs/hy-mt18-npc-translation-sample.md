# HY-MT1.5-1.8B：真实 NPC 台词离线翻译实测

日期：2026-09-11。Apple M4 / 16GB Mac，mlx-lm 0.31.3、mlx 0.32.2。此次仅评估模型，未集成到 App，未启动全词典预翻译。

## 体积

使用 [mlx-community/HY-MT1.5-1.8B-4bit](https://huggingface.co/mlx-community/HY-MT1.5-1.8B-4bit/tree/f6911967a04cfbeb2246a164fe1af5da2cc093ad)，固定 revision `f6911967a04cfbeb2246a164fe1af5da2cc093ad`。

权重文件 1,007,776,125 字节（约 1.01 GB / 961 MiB）；本次下载的整个模型目录逻辑大小为 1,017,532,917 字节（约 1.02 GB）。权重下载后 SHA-256 校验通过：`0a6ebd73fc9be7887e92c46b38f274ef3d04534bad05affd34db50f9b3e0ee4b`。

这是 Mac MLX 模型资源的实际大小，不是已测量的 iOS 安装包增量。手机侧采用的格式、推理运行时和打包压缩会影响最终大小。直接随包提供会显著增加体积；更适合可选离线语言包，首次按需下载，下载后仍占设备空间。运行内存另计，尚未实测 iPhone 内存、速度、耗电或系统兼容性。

## 取样与方法

源文件：[departures_london_v1.json](../App/Resources/Stories/departures_london_v1.json)。固定选择 10 个 Oliver / Nora 节点，属于项目实际 NPC 剧情台词，不是线上私人聊天记录。覆盖口语、隐喻和英式幽默，属于定性小样本，并非随机抽样或总体准确率评测。

每次只输入该节点的英文原句，不输入前后文、角色设定或项目已有的中文译文。提示词为：`将以下文本翻译为简体中文，注意只需要输出翻译后的结果，不要额外解释：`，换行后接原句。采用模型卡推荐的 temperature 0.7、top_p 0.6、top_k 20、repetition_penalty 1.05，max_tokens 256；seed = 20260911 + 序号。

加载本地权重，启用 HF / Transformers 离线模式，没有调用付费翻译接口。以下每句仅生成一次，保留首次原始输出，没有润色或重试挑选。

## 原始输出

| 节点 | NPC 英文台词 | 模型原始译文 |
|---|---|---|
| hello | You found it. I was about to send you directions. | 你找到了它。我正打算给你发送详细的指引呢。 |
| hello_part2 | Three pubs and a very unreliable pigeon were my landmarks. | 三个酒吧，还有一只极其不可靠的信鸽，这些成了我的“地标”。 |
| cancel | One of our readers can't make it. A family thing. | 我们的读者中有一位无法参加。这是一家人的事情，需要全家一起来参与。 |
| nora_boundary | Not unless someone wants to. An empty slot isn't an emergency. | 除非有人愿意这么做。一个空闲的插槽并不是紧急情况。 |
| private_2_part2 | I want to hear what it sounds like outside my own head. | 我想听听，那些声音是从我自己的头脑之外传来的，该是什么样的呢。 |
| format_4 | Cheers for not volunteering me. | 感谢没有让我做志愿者工作。 |
| not_test | This isn't an audition. Nobody here needs to earn their chair. | 这不是试镜。这里没有人需要靠努力来获得自己的职位。 |
| read_yes_part2 | If I faint, please call it an experimental ending. | 如果我晕倒了，请称之为一次实验性的结局吧。 |
| remember_private | Thanks for asking what I wanted before trying to fix things. | 谢谢你在试图解决问题之前先询问了我的需求。 |
| next_day | Coffee tomorrow? I won't make you review the whole novel. | 明天要喝咖啡吗？我不会让你去通读整本小说的。 |

## 观察与结论

这批单句测试未达到直接替代在线整句翻译的质量要求：

- `cancel`：A family thing 指家里有事，模型凭空扩写成“需要全家一起来参与”；readers 在活动语境下也是朗读者。
- `nora_boundary`：slot 是活动空缺名额，译成“插槽”错域。
- `private_2_part2`：原句指想听作品读出来的效果，译文变成脑外传来的声音，偏离语境。
- `format_4`：not volunteering me 指没有擅自替我报名，译成“没有让我做志愿者工作”失准。
- `not_test`：earn their chair 是不必证明资格才配坐在这里的隐喻，译成“获得自己的职位”错域。
- `next_day`：review 在这里是评论小说，不是单纯通读。
- `hello_part2`：pigeon 额外具体化为“信鸽”。

简单直述句及晕倒的玩笑可理解，但自然程度不稳定。本次结果只能说明该量化版本在这组无上下文台词上的表现，不能据此断言所有 1.8B 场景均不适用；也不能与此前带词义上下文的 7B 词典测试直接比较。下一步若继续评估，应对相同台词提供真实英文对话上下文，再与 7B 使用相同输入比较；不能先承诺上下文一定能解决错误。

模型加载 0.52 秒，10 句生成合计 4.17 秒，中位数 0.44 秒，范围 0.33–0.48 秒。仅为本次 Mac 观测，不代表 iPhone 时延或冷启动性能保证。

Tokenizer 报告部分 rope_parameters 扩展键未识别；MLX 推理正常完成 10 句，未测试长上下文。

## 复现

```sh
python Scripts/sample-local-npc-translation.py \
  --model-path /absolute/path/to/HY-MT1.5-1.8B-4bit
```

默认原始记录输出至 `build/verification/hymt18-npc-translation/output.json`（生成文件不提交），包含模型 revision、节点 ID、完整提示词、seed、首次输出及逐句用时。模型文件保存在本机缓存，不随 Git 提交。
