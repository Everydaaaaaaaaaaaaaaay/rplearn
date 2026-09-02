# Supertonic-3 随包模型来源

- Core ML 仓库：`FluidInference/supertonic-3-coreml`
- 固定提交：`9f3606bf5c5ff9d6680cf6226614ac61358a24f3`
- 上游模型：`Supertone/supertonic-3` v1.7.3
- 上游模型提交：`3cadd1ee6394adea1bd021217a0e650ede09a323`
- 本地模型目录：`Models/supertonic-3`（FluidAudio 的固定缓存目录名）
- VectorEstimator：ANE bucketed INT4（L128/L256/L512）
- 输出：44.1 kHz 单声道 Float32 PCM
- 模型许可证：BigScience OpenRAIL-M
- FluidAudio SDK：Apache License 2.0

固定资源包含 38 个文件、171602494 字节。构建前会核对文件数、总字节，以及六个
Core ML 权重的大小和 SHA-256。模型的完整 OpenRAIL-M 文本随资源存放于
`SUPERTONIC3_MODEL_LICENSE.txt`。

注意：FluidAudio 0.15.5 的局部文档曾把 Supertonic-3 权重误写为 Apache 2.0；
上游模型卡与许可证文件均明确为 OpenRAIL-M，本项目以原始上游许可证为准。
