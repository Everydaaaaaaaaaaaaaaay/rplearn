# 低成本实时语音架构

## 产品目标

实时语音以 GPT Live 的可感知体验为目标：持续双工、流式字幕、自然端点、用户开口即可打断、
AI 边生成边说、正确处理后台和电话中断。这里追求交互体验接近，不声称复制 ChatGPT 未公开的
音频模型、路由或服务端实现。

模型成本边界固定为：语音识别使用 Apple 系统 Speech，角色回复复用现有服务端低成本流式
LLM，TTS 使用随包 Pocket TTS。没有外置 ASR、OpenAI Realtime、WebRTC 服务或新增按分钟
语音账单。

```text
麦克风 PCM
    │
    └─ Apple Speech ────────────────────► partial + final
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

ASR 统一采用 `SFSpeechRecognizer`：优先请求设备端英语识别；当前语言模型不可用时允许 Apple
系统服务兜底。应用不再打包 Parakeet 或 SenseVoice，也没有 ASR 冷启动模型加载阶段。

Pocket TTS 的 INT8 Core ML 管线与 7 套英语音色共 30 个文件、331440634 字节，从 SpeechKit
只读 Bundle 加载。语音模型资源因此从约 796MB 降至约 331MB。

Pocket TTS 模型固定到上游提交并通过 Git LFS 管理大权重。资源包携带来源清单和 CC BY 4.0
归属。开发机或 CI 拉取代码后必须执行 `git lfs pull`；Xcode 的预构建阶段会执行
`Scripts/verify-bundled-voice-models.sh`，缺文件、LFS 指针未展开、文件数、总字节或关键权重
SHA-256 不匹配时直接终止构建。

上游资料：

- [Pocket TTS Core ML 模型卡](https://huggingface.co/FluidInference/pocket-tts-coreml)
- [Pocket TTS 上游项目](https://github.com/kyutai-labs/pocket-tts)
- [Apple App 上传大小限制](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes)

## 关键交互机制

- `AVAudioSession.voiceChat` + VoiceProcessingIO 保持播放和录音同时工作，并使用系统 AEC 抑制
  Pocket TTS 回声。
- 能量门连续两帧确认用户开口，立即取消 LLM 流和 TTS；不等待 ASR 完整识别后才打断。
- Apple Speech 的 final 是主端点；partial 长时间不再变化时强制定稿作为漏报兜底。
- LLM token 遇到标点立即送播；长时间无标点时最多累计 7 个单词，降低首段 TTS 等待。
- TTS 队列等待音频真正播放结束，不把“合成完成”误当成“播放完成”。插话时只落库已经开播的
  短句，并保留 `isInterrupted`。
- Pocket TTS 未预热或运行失败时沿用 Apple TTS 回退；模型在 App 启动后按当前选择后台预热。
- ASR 固定为 Apple Speech；TTS 选择立即生效。业务 Feature 只依赖稳定协议，不接触 Speech、
  FluidAudio、Core ML 路径或模型状态细节。

## 生命周期

`RealtimeVoiceSession` 是唯一 UI 状态源：

```text
idle → connecting（启动系统识别）→ listening ⇄ userSpeaking
                                                │ final/兜底端点
                                                ▼
                                             thinking → speaking
                                                ▲          │
                                                └─ 用户插话 ┘

任意活动状态 → paused（后台/电话中断）→ 原地恢复
权限、系统识别或音频错误 → failed → 重试或打开系统设置
```

Apple 系统识别优先端侧模型，不可用时允许系统服务兜底。LLM 网络失败是单轮非致命错误：
保留已经播出的内容并回到监听，而不是销毁整个会话。

## 隐私和成本

- 原始 PCM 不由应用上传或落盘；Apple 系统识别是否使用网络由设备的语言模型可用性决定；
- 只有 Apple Speech 的终稿文本进入现有 LLM 请求和聊天记录；
- 无新的服务端密钥、Realtime 会话路由、WebRTC SDK 或供应商依赖；
- LLM 继续由 `LLMRouter` 选择现有配置，默认生产路径仍可使用 DeepSeek-v4-flash；
- Pocket TTS 为端侧固定成本；Apple 系统识别不引入应用侧按分钟账单。

## 真机验收门槛

构建和模拟器测试不能替代声学验收。发布前至少在一台中端支持 ANE 的 iPhone 上记录 p50/p95：

- 缓存模型后，进入页面到可说话 p95 ≤ 1.5 秒；
- 流式字幕相对说话 p95 ≤ 550 毫秒；
- 用户自然说完到发出 LLM 请求 p95 ≤ 900 毫秒；
- DeepSeek 首 token 到第一段 TTS 开播 p95 ≤ 900 毫秒；
- 播放中开口到声音停止 p95 ≤ 250 毫秒；
- 10 分钟连续对话无重复落库、无自回声误触发、无漏掉第二轮；
- 单独覆盖扬声器、AirPods/HFP、静音、前后台、电话中断、拒绝权限、弱网和系统识别不可用。

上述数字是验收目标，不是在模拟器中测得的完成值。真机日志应分别记录 ASR partial/final、
LLM 首 token、TTS 首帧和播放器实际开播时间，避免用总体主观感受掩盖瓶颈。
