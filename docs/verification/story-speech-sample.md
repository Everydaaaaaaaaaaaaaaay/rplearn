# 伦敦剧情语音演绎样板

范围：`departures_london_v1` 的 `small` → `two_ways_part2`，10 条有声台词。
取材于 Oliver 提出试读条件、Nora 接住请求、大家留出空间、Oliver 重新看见选择的段落。
中间玩家的 `clarify` 台词在 App 中保持静音；纯音频样板省略该节点，不能代表完整互动时长。

## 已实现

- 剧本可选 `speech` 元数据记录每句的情境/意图、语速、前后留白及一个可选的完整句间停顿。
  运行时按当前节点读取；分支和存档恢复天然选择对应方向，无额外模型调用或隐含情绪状态。
- 角色身份和演绎分开：Oliver 仍为 M5，Nora/旁白仍为 F5。样板外的 103 个节点维持原设置。
- 10 句试行语速为 0.94–1.02；大多数整句合成，保留模型从文字/标点中形成的自然韵律。
  只在 `small` 的 `A small beginning.` 后显式分段加入 180 ms 留白，对照验证断句的收益与代价。
- `silence_part2` 旁白结束后加入 550 ms 留白；在接下来的 Oliver 台词 `two_ways`
  才加入 `<breath>`，不让旁白替人物喘气。不因“担心”“释然”就机械加叹气或笑声。
- 表达标签仅进入 Supertonic 朗读输入，字幕、翻译、查词与历史均保留原文。
  Apple 回退读取原文并保留语速、前后停顿；不支持的标签和句中精细停顿降级为自然整句朗读。
- 前后/句间留白写入同一次 PCM，完成事件包含它们；沿用现有切页/查词/退出的取消机制。
  词典请求忽略剧情方向，既有词典缓存不失效；缓存身份为未来的剧情缓存保留了演绎区别。
- 不改故事 ID、版本、节点或选择，现有样章存档继续可用。

这是人工根据场景编排、运行时自动选用的样板，不声称已覆盖所有剧情，也不声称具备任意情绪控制。

## 对照和再现

`SpeechDeliveryAuditionTests` 是显式开启的本地模型实验，普通单元测试默认跳过。
它调用 App 的 `LondonEpisodeNarration` 和 `Supertonic3SpeechEngine.synthesizeSamples`，
使用随包 v1.7.3 / FluidAudio 0.15.5 / ANE INT4 三档 / 8 步 / 44.1 kHz，不替换模型或音色。

- `original`：当前基线，原文、速度 1.0，无新增留白或标签。
- `rhythm`：逐句语速与留白，无表达标签。
- `expressive`：在 rhythm 基础上仅给 `two_ways` 增加呼吸标签。

rhythm 与 expressive 的其余 9 句复用同一份 PCM，避免扩散采样随机性影响标签对照。
不对各版本单独响度归一化；IEEE float WAV 保留原始振幅。各句之间保留 App 自动播放的 600 ms
基础等待。离线拼接样板不含现场合成等待、页面动画或雨声，不用于推断真机交互延迟。
当前接口未暴露随机种子；发生重新合成的句子仍有采样变异，不能据一次对照归因全部听感差异。

再现命令和本次结果见后续记录。生成音频、xcresult 和下载的 ASR 权重存于本地 build/cache，不提交。

## 验证分层

1. 确定性回归：原文无丢失、音色一致、旁白/人物边界、旧剧本兼容、错误停顿定位拒绝、词典隔离、
   缓存身份、切页/查词/退出生命周期、现有四种故事路径。
2. 真实本地合成：每句 PCM 非空/有限/有声、时长与峰值，导出整段和逐句音频。
3. 本地 ASR 辅助：检查漏词/重复/标签读出候选；识别差异必须人工听辨，不把 ASR 当语音真值。
4. 听感验收：先看场景意图，再盲听版本，评自然度、场景适配、角色一致性（各 1–5 分）；
   单列“呼吸是否突兀”“分句是否像重新起句”“语速是否拖沓”。由人试听确认，技术通过不等于听感通过。

不能用自动化断言验证“悲伤/温柔真的像真人”。未完成听感确认前，不将样板参数推广到全量故事。

## 2026-09-07 实测

- iOS 26.1 独立 QA 模拟器：43 项通过（参数展开 46 次执行），0 失败、0 跳过。
  覆盖 SpeechDeliveryTests、SpeechDeliveryAuditionTests、SpeechServiceTests、
  NarrativeAudioPlayerTests、StoryEpisodeTests。
- 导出 30 份逐句 WAV、3 份整段 WAV 与逐句指标。三版分别约 40.02、43.67、44.14 秒。
  全部样本有限、有声；三版最大绝对振幅分别 0.343、0.371、0.371，没有数字削波。
- 本地 faster-whisper/base.en 逐句识别：rhythm 与 expressive 均无词级编辑差异，
  没有识别出多余的 “breath” 一词。original 有两处识别缺词候选（a / and），
  尚未人工确认，不据此断言原版实际漏读或调整版一定更好。
  `small` 的识别结果存在多余标点，原样保留在 ASR 记录中；词级比对忽略标点。
- `<breath>` 所在句约从 4.94 秒变为 5.41 秒，识别正文完整；这只支持标签可进入实际模型
  且本次未被 ASR 检出正文干扰，不能凭时长证明呼吸听起来真实。人工听感评分尚未完成。
- 初次复用旧 DerivedData 时遇到旧 StoryEngine 接口；独立 DerivedData 消除该构建问题。
  随后修复试听测试缺少 CoreKit import，最终上述 43 项通过。没有真机安装或性能结论。

简要指标与音频散列：[结果记录](../data/story-speech-sample-2026-09-07.json)。
当前本地试听入口：`build/verification/story-speech-20260907/index.html`；同目录包含逐句原始 PCM WAV、
整段音频、`speech-audition-metrics.json` 与 `asr-review.json`。
测试证据：`build/DerivedData-speech-direction/VerificationResults/20260906T200657Z-38297.xcresult`。

重新生成（显式本地模型评估，不自动加入日常门禁）：

```bash
LINGOTRIP_SIMULATOR_UDID=25F3EB64-EE97-4560-A3A0-9DD8D1363468 \
LINGOTRIP_DERIVED_DATA_PATH="$PWD/build/DerivedData-speech-direction" \
Scripts/audition-story-speech.sh build/verification/story-speech-new

# 可选识别检查：首次下载 ASR 模型；音频始终本地处理。
uv run --with faster-whisper Scripts/evaluate-story-speech.py build/verification/story-speech-new
```

已有 xcresult 可只运行 `python3 Scripts/export-story-speech.py RESULT_PATH OUTPUT_DIRECTORY`，
无需重新合成。输出目录的每次全新合成应使用新名称，保留先前对照。
