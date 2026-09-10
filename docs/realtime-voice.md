# 低成本实时语音架构

## 产品目标

实时语音以 GPT Live 的可感知体验为目标：持续双工、流式字幕、自然端点、用户开口即可打断、
AI 边生成边说、正确处理后台和电话中断。这里追求交互体验接近，不声称复制 ChatGPT 未公开的
音频模型、路由或服务端实现。

模型成本边界固定为：语音识别使用 Apple 系统 Speech，角色回复复用现有服务端低成本流式
LLM，TTS 使用随包 Supertonic-3。没有外置 ASR、OpenAI Realtime、WebRTC 服务或新增按分钟
语音账单。

```text
麦克风 PCM
    │
    └─ Apple Speech ────────────────────► partial + final
                                      │
                                      ▼ 仅文本
                         后台 conversation 任务当前配置的模型
                                      │ 流式 token
                                      ▼
                       首段 7 词 / 后续 14 词 + Supertonic / Apple TTS
                                      │
                                      ▼
                          VoiceProcessingIO 双工播放
```

## 模型选择

ASR 统一采用 `SFSpeechRecognizer`：优先请求设备端英语识别；当前语言模型不可用时允许 Apple
系统服务兜底。应用不再打包 Parakeet 或 SenseVoice，也没有 ASR 冷启动模型加载阶段。

Supertonic-3 的 ANE INT4 Core ML 管线与 10 套英语音色共 38 个模型文件、171602494 字节，
从 SpeechKit 只读 Bundle 加载。相较此前的 Pocket TTS，模型资源减少约 160MB。

Supertonic-3 模型固定到上游提交并通过 Git LFS 管理大权重。资源包携带来源清单和完整
BigScience OpenRAIL-M 许可。开发机或 CI 拉取代码后必须执行 `git lfs pull`；Xcode 的预构建阶段会执行
`Scripts/verify-bundled-voice-models.sh`，缺文件、LFS 指针未展开、文件数、总字节或关键权重
SHA-256 不匹配时直接终止构建。

上游资料：

- [Supertonic-3 Core ML 模型卡](https://huggingface.co/FluidInference/supertonic-3-coreml)
- [Supertonic-3 上游模型](https://huggingface.co/Supertone/supertonic-3)
- [Apple App 上传大小限制](https://developer.apple.com/help/app-store-connect/reference/app-uploads/maximum-build-file-sizes)

## 关键交互机制

- `AVAudioSession.voiceChat` + VoiceProcessingIO 保持播放和录音同时工作，并使用系统 AEC 抑制
  Supertonic-3 回声。
- 能量门连续两帧确认用户开口，立即取消 LLM 流和 TTS；不等待 ASR 完整识别后才打断。
- Apple Speech 的 final 是主端点；partial 不再变化且没有持续说话声时，才强制定稿作为漏报兜底。
  初学者静音兜底为 1.8 秒，其他级别为 1.0–1.5 秒。`endAudio` 后 500ms 仍没有 final 时，
  用最新转录结束该轮；旧识别回调立即失效，避免重复请求和丢失下一轮。
- 首段最多累计 7 个完整单词，后续可累计 14 个；优先沿句子/分句边界切分。小数点、常见称谓
  和缩写不立即拆开；末尾句点等待下一个增量或流结束判定。
- 当前短句真正开播后，才预合成下一句，最多保留一段待播 PCM；模型生成、当前播放和下一段
  本地合成可重叠。Apple TTS 回退仍按句播放。Supertonic 是分句合成，不是逐音频 token 输出。
- 播放通知带请求 ID，旧请求或其他页面的播放不会污染通话状态。界面在真实开播时显示“说话”。
- TTS 队列等待音频真正播放结束，不把“合成完成”误当成“播放完成”。插话时只落库已完整播放的
  短句，并保留 `isInterrupted`。没有词级音频对齐，因此被打断的当前短句保守省略，不能把整句
  都算成用户已听到。停止先中止音频，再等待本地预合成清理；新回复等待旧输出清理结束。
- Supertonic-3 是英语合成的默认引擎；新安装直接启用，旧安装在升级后的首次启动中
  自动从 Apple/Pocket 旧偏好迁移，并在 App 启动后后台预热。用户随后主动选择 Apple
  时仍保留该选择；Supertonic-3 未预热或运行失败时继续使用 Apple TTS 回退。
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
- LLM 使用后台 `conversation`（聊天回复）的配置，包括管理员选择的 GLM。
  独立的 `speech_feedback` 口语点评已移除，服务端在模型调用和额度操作前拒绝旧版请求。
  聊天页单独发送的语音消息继续保留录音、时长、转写和点击播放；LLM 只接收转写文本，
  沿用普通聊天处理。实时通话仍遵循上面的 PCM 不落盘策略。
  历史点评字段保留以兼容旧数据同步，但不再展示点评卡或生成新点评；
- Supertonic-3 为端侧固定成本；Apple 系统识别不引入应用侧按分钟账单；
- 用户模型积分仍按实际用量结算，不为 TTS 新增扣费。语音 lease 是服务端会话许可，不是用户
  积分冻结；续期失败时关闭新输入，等已开始的回复播放结束再挂断。用户主动挂断仍立即停止。
  已派发的模型调用可能继续在服务端收集用量并结算，不把客户端取消当成免费调用。

## 真机验收门槛

构建和模拟器测试不能替代声学验收。发布前至少在一台中端支持 ANE 的 iPhone 上记录 p50/p95：

- 缓存模型后，进入页面到可说话 p95 ≤ 1.5 秒；
- 流式字幕相对说话 p95 ≤ 550 毫秒；
- 高级用户自然说完到发出 LLM 请求目标 p95 ≤ 900 毫秒；初学者需同时验证思考停顿不被抢话；
- 配置模型首 token 到第一段 TTS 开播 p95 ≤ 900 毫秒；
- 播放中开口到声音停止 p95 ≤ 250 毫秒；
- 10 分钟连续对话无重复落库、无自回声误触发、无漏掉第二轮；
- 单独覆盖扬声器、AirPods/HFP、静音、前后台、电话中断、拒绝权限、弱网和系统识别不可用。

上述数字是验收目标，不是在模拟器中测得的完成值。真机日志应分别记录 ASR partial/final、
LLM 首 token、TTS 首帧和播放器实际开播时间，避免用总体主观感受掩盖瓶颈。

## 2026-09-11 改造与验证记录

本次复用 Apple ASR、现有流式聊天接口和 Supertonic-3，无新增供应商、密钥或依赖。
修复短句合成串行等待、静音端点误判、漏报 final、挂断后终稿排队发送、插话输出竞态，
以及续期失败中途截断已开始回复的问题。错误原因会显示在通话页面，不再只隐藏在会话状态中。

回归覆盖分句、小数和缩写、单段预合成及消费、播放通知隔离、插话后的已听记录、持续说话、
重复 partial、挂断后的回调、上游取消和余额不足时完成当前回合。测试使用模拟输入/播放，
不调用付费模型；`SpeechServiceTests` 同时验证原有引擎路由和音色策略。
本次 37 项测试通过，0 失败、0 跳过；iOS 模块依赖检查通过。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
LINGOTRIP_DERIVED_DATA_PATH="$PWD/build/DerivedData-RealtimeVoice" \
Scripts/test.sh \
  -only-testing:LingoTripTests/RealtimeVoiceSessionTests \
  -only-testing:LingoTripTests/StreamingSpeechSegmenterTests \
  -only-testing:LingoTripTests/RealtimeSpeechOutputTests \
  -only-testing:LingoTripTests/SpeechServiceTests
Scripts/check-architecture.sh --ios
```

真机声学与性能验收仍待执行：不能用模拟器/模拟播放测试宣称扬声器回声、蓝牙路由、首声延迟
或 10 分钟连续对话已达标。Apple 识别准确率、设备端合成速度和所配模型首 token 延迟均影响体验。
