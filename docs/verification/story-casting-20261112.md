# 剧情声线与节奏调整

2026-11-12。26 个配音身份的统一来源为 [随包选角表](../../App/Resources/StoryVoices/story-voice-cast.json)，运行时与离线制作计划共同读取。

| 身份 | 声线 | 基础语速 | 常规句尾停顿 |
| --- | --- | --- | --- |
| Ruby | F3 | 1.06 | 0.24 秒 |
| Oliver | M5 | 1.00 | 0.32 秒 |
| 旁白 | F5 | 0.99 | 0.38 秒 |
| Nora | F2 | 1.02 | 0.28 秒 |
| Isla | F1 | 1.04 | 0.30 秒 |

其余角色逐一登记于选角表。固定剧情角色使用 F1–F4、M1–M5，旁白使用 F5。语言字段用于系统回退的地区选择，Supertonic 使用所登记的声音风格。

场景速度乘以角色基础速度。常规角色台词按角色停顿上限收束，结尾保留剧本留白。自动阅读直接等待音频中已有的句尾停顿结束。预制音频检查原文、角色、声线及当前语速，匹配失败时使用当前请求现场合成。

约定剧情区分 `character` 与 `narrator`，角色请求从账号角色卡取身份，并应用统一选角。翻页、静音、回看和查词时暂停原台词。显式声线在合成引擎中优先于国籍推断。

验证覆盖全部 25 个保留阅读版本的逐角色请求，以及当前 20 个目录入口。Swift 定向测试 37 项通过，Python 制作计划测试 4 项通过。Swift 证据为 `build/DerivedData/VerificationResults/20261112T092129Z-66792.xcresult`。

最终地区回退兼容、可用预制与现场合成请求检查重跑 7 项通过，证据为 `build/DerivedData/VerificationResults/20261112T093529Z-71507.xcresult`。模拟器与真机构建中的选角 JSON 均已与当前源文件逐字节比对。

真实模型试听测试 1 项通过，生成 Ruby 三句、Oliver 两句、Nora 两句与旁白两句。音频及参数位于 `build/verification/story-casting-20261112/`，结果包为同目录 `run.xcresult`。使用 App 正式请求与随包模型生成。

离线 Whisper small 转录检查保留了差异。Ruby 的 `has` 被转录成 `is`，Oliver 的 `pigeon` 被转录成 `pageant`，旁白的 `Ruby brings` 被合并成 `Rebrings`，Nora 两句一致。原文、转录及逐组差异见同目录 `recognition.json`。这些样本仍待听音确认，尚未完成全量逐句情绪验收。

Ruby 界面实播回归 1 项通过，覆盖旁白 F5、Ruby 台词 F3、开启后的真实播放通知与静音。证据为 `build/DerivedData/VerificationResults/20261112T092617Z-69829.xcresult`。测试完成后 Xcode 的模拟器诊断采集停滞，终止了该诊断子进程，结果包成功收尾，测试为 1 通过、0 失败、0 跳过。

当前源码已构建并安装至连接的 iPhone 13，启动在主线列表。通过 `Scripts/preview.sh preview home` 安装的模拟器停在 Ruby 新版章节，声音关闭，可手动开启试听。Computer Use 已查看该章节首屏。
