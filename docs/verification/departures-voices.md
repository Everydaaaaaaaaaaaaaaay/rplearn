# 新故事集配音验证（2026-09-07）

范围为 `departures_catalog.json` 中的五站主线和十五篇城市故事，包括所有分支。剧情设计与当前接入边界见 [故事集设计](../departures-collection.md)。这里记录的是一次明确启动的本地资产制作与验收，不是普通提交必须重跑的模型门禁。

## 制作方法

1. `plan-story-voices.py` 读取实际双语脚本与 `Scripts/data/story-voice-directions.json`，固定角色声线，并使用逐场景的语速、呼吸和停顿。玩家回应、选项不配音。
2. 使用 App 已解析的 FluidAudio SDK、同一套 Supertonic 3 ANE int4 模型与 voice styles。在 Mac 的 CPU/Neural Engine 上制作候选；伦敦第一批也通过 Xcode 显式生产测试生成。同一完整句子的实际输入限制为 70 个 NFKD 字符，表达标签计入；切分不丢词，不将不完整音频裁成“合格”。
3. 每个片段制作四个候选：两次 12 步、一次 8 步，以及轻微速度变化或去掉呼吸标签的候选。先用 Whisper base.en 转录；无合格候选时用独立 small.en 复核，不向识别器提供期望台词。保留原转录、音频散列与拒绝原因。
4. 从转录通过、没有削波的候选中选择时长与响度居中的版本，并优先避开瞬时峰值过高的候选。只修剪保守的静音边缘，保留 100 ms 前沿与 120 ms 尾部。角色固定增益最多 ±1.5 dB，再对整体施加恒定增益，以约 −22 LUFS 为目标；没有逐句响度拉平、语音交叉淡化、变调、压缩或混响。
5. 句末停顿计入已保留尾部和下一句前沿，避免停顿叠加。输出 AAC 96 kbps，并重新解码检查时长和峰值。清单绑定故事、节点、说话人、原文和音频 SHA-256。
6. 对最终编码后的每一页重新用 small.en 转录，复核拼接与编码后的完整性。自动转录只能支持可懂度和文本完整性判断，不代表人类对情感或演技的评分。

识别比较允许标点、英美拼写、数字/英文数词、少量同音词与人名拼写等价；原始识别文本仍保留在报告中。比较不忽略漏词、否定词或数字差异。实际修复包括：温哥华开场的 Noah 名字连接不清，通过重写句式改善；伦敦 “An empty slot isn't an emergency.” 的否定词问题，通过按完整句子的原文停顿锚点重新制作解决，没有把 `isn't` 与 `is` 当作等价。

## 复现与有边界的检查

普通改动按影响选择测试，不需要全部运行。需要重新制作声音时，先准备已构建 App 的模型目录以及 Python 环境（numpy、num2words、MLX Whisper 或 faster-whisper；FFmpeg 在 PATH 中），再显式执行：

```sh
voice_output="$PWD/build/verification/departures-voices-20260907"
voice_models="$PWD/build/DerivedData-speech-direction/Build/Products/Debug-iphonesimulator/LingoTrip.app/LingoKit_SpeechKit.bundle/Supertonic3/Models"
python Scripts/plan-story-voices.py "$voice_output"
Scripts/produce-story-voices-mac.sh "$voice_output" "$voice_models"
STORY_VOICE_ASR=mlx python Scripts/produce-story-voices.py screen "$voice_output"
STORY_VOICE_ASR=mlx python Scripts/produce-story-voices.py master "$voice_output"
STORY_VOICE_ASR=mlx python Scripts/verify-story-voice-library.py App/Resources/StoryVoices "$voice_output" --recognize
python Scripts/audition-story-library.py App/Resources/StoryVoices "$voice_output/index.html"
```

Python 环境由操作者选择；上述命令不安装或更新 App 模型/SDK。制作工具复用内容相同的候选。转录差异必须检查 `final-library-check.json` 的 `transcriptDisagreements`，不能只看命令退出码。候选 WAV、模型缓存和完整制作日志保留在忽略的 `build/` 中，不加入 Git。随包资源、制作脚本及简要事实报告加入版本管理。

确定性检查：

```sh
python Scripts/test_story_voice_library.py
Scripts/test.sh -only-testing:LingoTripTests/DepartureCollectionTests -only-testing:LingoTripTests/SpeechDeliveryTests -only-testing:LingoTripTests/StoryVoiceLibraryTests
Scripts/test-ui.sh -only-testing:LingoTripUITests/DepartureCollectionTests -only-testing:LingoTripUITests/LondonEpisodeTests/testDismissingLookupDoesNotRepeatNarration -only-testing:LingoTripUITests/LondonEpisodeTests/testEntryThroughStoryHub
```

实测使用独立模拟器 `25F3EB64-EE97-4560-A3A0-9DD8D1363468` 和 `build/DerivedData-speech-direction`，通过 `LINGOTRIP_SIMULATOR_UDID` / `LINGOTRIP_DERIVED_DATA_PATH` 指定，未操作其他工作树的模拟器。

## 本批实测与验收

- 20 篇、562 个节点、50 条完整选择路径；462 页英文配音、100 页玩家/选项文字。
- 464 个合成片段，当前保留 1,856 个候选 WAV；最终随包为 462 个 AAC 文件。候选数量不包含已被原位替换的失败尝试。
- 最终解码总时长 1,560.17 秒（约 26 分钟），音频文件合计 19,325,787 字节（约 19.3 MB）。全量原文绑定、SHA-256、真实解码与峰值检查通过；small.en 复核 462/462 页，按上述规则归一化后未解决差异为 0。最后替换的 Toronto 结尾候选也包含在这次核验中，保留了原句中的 `dessert`。
- 最终编码文件拼接测量：**−23.34 LUFS、−1.75 dBTP、LRA 2.70 LU**。−22 LUFS 是基准目标；为保留动态与峰值余量，本批使用恒定增益得到上述实际值，未把测量滤镜模拟的归一化输出当作已发布数据。
- 播放服务与原声音方向的初次整合验证：20 项通过（`20260907T093539Z-21801.xcresult`）。最终资源再次验证：7 项通过（`20260907T100537Z-34023.xcresult`），覆盖每一页原文/声线/音频解码、所有路径与逐页检查点。
- Python 制作计划检查：4 项通过，包含漏词、数字与否定词不能被归一化吞掉的验证。
- UI：4 项通过（`20260907T100143Z-31611.xcresult`）：新纽约主线的播放、两次分支和退出续读；曼彻斯特的播放、翻译与查词返回；伦敦查词及发音后不重播；从正式首页剧情入口进入新目录。已检查曼彻斯特阅读页及纽约结尾截图。
- 首次最终资源测试曾因模拟器未能启动 App 而未执行；重新启动本次专用模拟器后复验通过，未清除应用数据。

完整本地证据在 `build/verification/departures-voices-20260907/`，Xcode 证据在 `build/DerivedData-speech-direction/VerificationResults/`。最终识别与文件统计摘要见 [可审阅的数据](../data/departures-voices-20260907.json)。试听页为同目录 `index.html`，嵌入全部音频并保留分支选择，不需要服务器或账号。

本次不宣称完成十九篇的专属立绘/分镜，也不宣称跨设备故事进度、跨篇关系记忆、正式奖励切换或真机性能验收。预制声音缺失或损坏时回退合成；回退用于继续阅读，不承诺与已挑选及后期处理的预制演出完全一致。
