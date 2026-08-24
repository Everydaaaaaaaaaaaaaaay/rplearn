# 低成本实时语音架构

## 产品目标

实时语音以 GPT Live 的可感知体验为目标：持续双工、流式字幕、自然端点、用户开口即可打断、
AI 边生成边说、正确处理后台和电话中断。这里追求交互体验接近，不声称复制 ChatGPT 未公开的
音频模型、路由或服务端实现。

模型成本边界固定为：增强模式下原始音频端侧处理，角色回复复用现有服务端低成本流式 LLM，
TTS 使用随包 Pocket TTS。设置页也保留 Apple 系统 ASR/TTS，方便在同一设备上 A/B 对比。
没有 OpenAI Realtime、WebRTC 服务或新增按分钟语音账单。

```text
麦克风 PCM
    │
    ├─ 增强：Parakeet EOU 120M / 320ms ─► 流式字幕 + 语义端点
    │         └─ SenseVoice Small INT8 ─► 完整话轮终稿校正
    └─ 系统：Apple Speech ──────────────► partial + final
                                      │
                                      ▼ 仅文本
                         现有 LLM 路由 / DeepSeek-v4-flash
                                      │ 流式 token
                                      ▼
                         7 词短句切分 + Pocket / Apple TTS
                                      │
                                      ▼
                          VoiceProcessingIO 双工播放
```

## 模型选择

### Parakeet EOU 120M

- 真流式 RNNT，缓存感知编码器，不需要反复重跑整段音频；
- 使用 320ms 版本。FluidAudio 的 LibriSpeech test-clean 基准约 4.88% WER、19.25x RTF，
  精度明显优于 160ms 版本，同时字幕延迟仍足够低；
- 模型自带 EOU token，比固定静音计时更能区分自然停顿和真的说完；
- 安装资源包含 3 个编译后的 Core ML 图和词表，共约 224MB。

### SenseVoice Small INT8

SenseVoice 是批处理 CTC 模型，不适合单独承担实时字幕。它在每个完整话轮结束后只执行一次，
用来校正 Parakeet 的终稿。FluidAudio 公布的 INT8 版本约 225MB，LibriSpeech test-clean WER
3.25%，相对 FP16 的 3.22% 只差 0.03 个百分点；连同预处理器和词表实际约 240MB。

两套 ASR 共 25 个文件、464151912 字节，作为 SwiftPM `.copy` 资源随 App 安装并从只读 Bundle
直接加载。Pocket TTS 的 INT8 Core ML 管线与 7 套英语音色共 30 个文件、331440634 字节，同样
从 SpeechKit 的只读 Bundle 加载。安装包因此固定包含 795592546 字节模型资源，约 796MB，不再
有首次使用下载。项目最低系统为 iOS 18，仍低于 Apple 对该部署目标 4GB 的 App Bundle 上限。

模型固定到上游提交并通过 Git LFS 管理大权重。资源包同时携带来源清单、Pocket TTS CC BY 4.0
归属、SenseVoice MIT 许可证、NVIDIA Open Model License PDF 和 NVIDIA 要求的 Notice。开发机
或 CI 拉取代码后必须执行 `git lfs pull`；Xcode 的预构建阶段会执行
`Scripts/verify-bundled-voice-models.sh`，缺文件、LFS 指针未展开、文件数、总字节或关键权重
SHA-256 不匹配时直接终止构建。

上游资料：

- [FluidAudio SenseVoice 文档](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/ASR/SenseVoice.md)
- [FluidAudio 基准](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [Parakeet EOU Core ML 模型卡](https://huggingface.co/FluidInference/parakeet-realtime-eou-120m-coreml)
- [SenseVoice INT8 Core ML 模型卡](https://huggingface.co/FluidInference/sensevoice-small-coreml)
- [Pocket TTS Core ML 模型卡](https://huggingface.co/FluidInference/pocket-tts-coreml)
- [Pocket TTS 上游项目](https://github.com/kyutai-labs/pocket-tts)
- [Apple App 上传大小限制](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes)

## 关键交互机制

- `AVAudioSession.voiceChat` + VoiceProcessingIO 保持播放和录音同时工作，并使用系统 AEC 抑制
  Pocket TTS 回声。
- 能量门连续两帧确认用户开口，立即取消 LLM 流和 TTS；不等待 ASR 完整识别后才打断。
- Parakeet 的 EOU 是主端点；partial 1.0–1.35 秒不再变化时强制定稿作为漏报兜底，学习等级越高
  兜底越短。
- LLM token 遇到标点立即送播；长时间无标点时最多累计 7 个单词，降低首段 TTS 等待。
- TTS 队列等待音频真正播放结束，不把“合成完成”误当成“播放完成”。插话时只落库已经开播的
  短句，并保留 `isInterrupted`。
- Pocket TTS 未预热或运行失败时沿用 Apple TTS 回退；模型在 App 启动后按当前选择后台预热。
- 设置页的 ASR 选择在下一次实时会话构造时注入具体输入引擎；TTS 选择立即生效。业务 Feature
  只依赖稳定协议，不接触 Speech、FluidAudio、Core ML 路径或模型状态细节。

## 生命周期

`RealtimeVoiceSession` 是唯一 UI 状态源：

```text
idle → connecting（准备端侧模型）→ listening ⇄ userSpeaking
                                                │ EOU/兜底端点
                                                ▼
                                             thinking → speaking
                                                ▲          │
                                                └─ 用户插话 ┘

任意活动状态 → paused（后台/电话中断）→ 原地恢复
权限、模型或音频错误 → failed → 重试或打开系统设置
```

增强 ASR 首次进入只需把 Bundle 中的 Core ML 模型加载到本地推理引擎，界面展示分阶段加载
进度且启动不依赖网络；Apple 系统识别优先端侧模型，不可用时允许系统服务兜底。LLM 网络失败
是单轮非致命错误：保留已经播出的内容并回到监听，而不是销毁整个会话。

## 隐私和成本

- 增强 ASR 下原始 PCM 不上传、不落盘，模型只收到内存中的 16kHz 单声道浮点样本；Apple
  系统识别是否使用网络由设备的语言模型可用性决定；
- 只有端侧校正后的终稿文本进入现有 LLM 请求和聊天记录；SenseVoice 无有效结果时才回退
  Parakeet 终稿；
- 无新的服务端密钥、Realtime 会话路由、WebRTC SDK 或供应商依赖；
- LLM 继续由 `LLMRouter` 选择现有配置，默认生产路径仍可使用 DeepSeek-v4-flash；
- 随包 ASR 和 Pocket TTS 均为端侧固定成本，连续使用不产生按分钟费用。

## 真机验收门槛

构建和模拟器测试不能替代声学验收。发布前至少在一台中端支持 ANE 的 iPhone 上记录 p50/p95：

- 缓存模型后，进入页面到可说话 p95 ≤ 1.5 秒；
- 流式字幕相对说话 p95 ≤ 550 毫秒；
- 用户自然说完到发出 LLM 请求 p95 ≤ 900 毫秒；
- DeepSeek 首 token 到第一段 TTS 开播 p95 ≤ 900 毫秒；
- 播放中开口到声音停止 p95 ≤ 250 毫秒；
- 10 分钟连续对话无重复落库、无自回声误触发、无漏掉第二轮；
- 单独覆盖扬声器、AirPods/HFP、静音、前后台、电话中断、拒绝权限、弱网和模型加载失败。

上述数字是验收目标，不是在模拟器中测得的完成值。真机日志应分别记录 ASR partial、EOU、
SenseVoice 终稿、LLM 首 token、TTS 首帧和播放器实际开播时间，避免用总体主观感受掩盖瓶颈。
