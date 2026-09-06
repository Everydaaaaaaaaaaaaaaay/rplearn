# 伦敦语音：连贯演绎试听成品

2026-09-07，承接第一版 10 句样板。本轮目标是制作可直接试听的完整音频，
使用当前 Supertonic-3 的真实可用能力，保留剧情原文与固定角色声音。

## 制作决定

- 当前 FluidAudio 0.15.5 的 Latin chunk 上限实际为 **70 字符**，不是整个模型无限接受长段上下文。
  保留该上限（包括标签），不修改依赖或放宽已知的读取稳定性限制。
- 重新按句意划分 10 个合成片段，跨过 3 处原消息框边界：条件与担心、Nora 的确认与选择权、
  Oliver 的另一种选择与释然。86 个英文词保持原顺序，角色和选择边界不混合。
  这里改善的是局部上下文和片段衔接，不能声称给模型提供了整个剧情的隐式情绪理解。
- 每段生成 4 个候选：首选语速下两次 12 步采样、一次 8 步对照、一次小幅语速变化。
  呼吸位置的第四个候选改为无标签对照。没有把 12 步当成必然更好的声音；最终同时选中了 8 和 12 步。
- base.en 本地识别筛查 40 个候选，其中 35 个词级结果与原文一致，5 个存在差异。
  从识别一致且没有削波的候选中，按时长和有效响度接近同组中位数筛选，避免选择极端速度或音量；
  情境需要呼吸时，在表现接近的候选间适度优先带标签版本。保留全部候选和筛选依据。
  这是工程筛选，不是主观演绎评分，也不据 ASR 差异断言实际合成一定漏词。
- 仅修整极低能量的片段首尾静音，留出保护边界；带呼吸标签的片段不裁剪句首。
  不在单词内部剪切，不在语音上交叉淡化，不对声音做变调、降噪或压缩。
- 相邻片段的停顿按**前段已有尾部留白 + 后段已有句首留白 + 补入静音**计算，
  消除上一版 600 ms 翻页等待与合成留白的机械叠加。目标短于保留边界时保留边界，不硬剪呼吸。
  `Of course.` 后目标 180 ms，实际保留 220 ms；其他已编排片段间隙达到 220–1050 ms 的目标。
- 对每个角色施加固定、小幅的响度平衡，保留角色内部动态；Nora 约 +0.91 dB、旁白约 -0.17 dB、
  Oliver 0 dB。然后仅用线性增益匹配原版与整合版整体响度到 -22 LUFS，保留至少 2 dB 峰值余量。
- 可选环境版叠加项目内原创合成雨声，约低于有效人声 25 dB，淡入淡出；主交付仍包含纯人声版本。
- 音频全部提前生成、选定并固定。试听播放没有现场模型等待。字幕按原文词序对齐回原来的 10 个节点，
  即使一个合成片段横跨两个消息框也保留原文归属；时标来自 ASR，是近似对齐。

这是一份预制试听包。尚未把分组音频与字幕时标接管 App 的全量分页、查词中断及预加载流程；
原伦敦样章的上一版节点级演绎不受影响。试听播放器能够在已准备的音频中定位台词和显示双语字幕。

## 当前输出

`build/verification/story-performance-20260907/`：

- `performance-dry.wav`：整合纯人声版，约 34.29 秒。
- `original-matched.wav`：原版，约 40.02 秒，已匹配整体响度。
- `performance-room.wav`：可选轻微书店雨声版本。
- `index.html`：内嵌三份音频与字幕的独立文件，支持台词定位，无外部素材依赖。
- `performance.vtt` / `timeline.json`：字幕与原节点时间表。
- `performance-review.json` / `candidate-review.json`：参数、候选依据、停顿与响度记录。
- `candidate-*.wav`：40 个原始采样候选，另保留 ASR 缓存与制作源数据。

脚本：`App/Resources/Stories/london_voice_performance_sample.json` 明确每个片段的原节点、原文、意图、
语速和停顿。App 托管的显式本地合成测试复用真实 `Supertonic3SpeechEngine`，不是另一套模型实现。

## 验证与再现

- Xcode：`StoryPerformanceCandidateTests` + `SpeechDeliveryTests`，5 项通过、0 失败、0 跳过。
  40 个候选全部完成随包模型真实推理；原文重组、角色一致、70 字符限制等断言通过。
- Python：5 项合成波形测试通过，覆盖极轻呼吸保留、语音样本不被修改、总停顿计算、
  不为缩短间隔截掉保留内容、非有限/削波/纯静音拒绝、识别词序比较。
- 浏览器：实测播放与字幕显示、台词定位。初版临时 HTTP 服务缺少 Range 导致定位归零，
  已改为内嵌音频；实测 seekable 为 0–34.29 秒，点击 Oliver 的选择台词跳转到 27.45 秒附近且字幕匹配。
  内置浏览器安全策略禁止 file:// 导航，因此没有宣称验证了直接打开本地文件这一浏览器操作；
  独立文件无外部依赖，音频也另行交付。
- 此轮没有进行人工听感评分或真机测时。不能凭识别准确、时长或波形推断“演技最佳”。

显式再现流程（本地 CPU/ANE 评估；首次 ASR 下载权重，音频不上传）：

```bash
LINGOTRIP_SIMULATOR_UDID=25F3EB64-EE97-4560-A3A0-9DD8D1363468 \
LINGOTRIP_DERIVED_DATA_PATH="$PWD/build/DerivedData-speech-direction" \
Scripts/audition-story-performance.sh build/verification/story-performance-new

python3 -m unittest discover -s Scripts -p test_story_speech_mastering.py
```

已有候选可运行 `uv run --with faster-whisper python Scripts/master-story-speech.py OUTPUT --baseline BASELINE.wav`
重做筛选/拼接，复用按模型与音频散列索引的本地识别结果，不重复合成。
每次全新渲染使用新目录，生成音频、下载权重、缓存与 xcresult 不提交。

### 完整成品的独立复核

另用 `small.en` 对整段成品重新识别（候选筛选使用的是 `base.en`），纯人声与环境版均为
86 / 86 个词、原顺序一致。原版仍有 a / and 两处识别缺词候选；没有把这个识别差异写成已人工
确认的原版配音错误。纯人声实测 -21.94 LUFS / -5.09 dBTP，环境版 -22.02 LUFS / -5.02 dBTP，
原版 -22.00 LUFS / -5.54 dBTP。整体响度差小于 0.1 LU，未使用峰值限制器制造响亮优势。

`Scripts/verify-story-performance.py OUTPUT --model small.en` 是可选显式复核，首次需要下载模型。
最终波形、候选选择、停顿、验证结果和散列：[本次结果](../data/story-speech-performance-2026-09-07.json)。
Xcode 证据：`build/DerivedData-speech-direction/VerificationResults/20260906T203549Z-43280.xcresult`。

没有新增日常门禁，没有部署服务器或安装手机。普通 App 播放仍默认 8 步；12 步仅由本地样板
候选制作显式调用。音频、独立试听 HTML、权重、缓存与临时输出留在本地，不进入 Git。
