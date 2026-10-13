# 研究Schema依赖离线重建

第11检查点首次重跑缺jsonschema，说明只保存工具和Python路径不足以恢复实际校验。现已冻结当时使用的六包：jsonschema4.25.1、attrs26.1.0、referencing0.37.0、jsonschema-specifications2025.9.1、rpds-py2026.9.1、typing_extensions4.16.0。每个wheel均与对应PyPI版本发布元数据的SHA256一致，许可与版权声明保留在研究缓存。

缓存`schema-runtime/requirements-hashed.txt`绑定全部版本和wheel摘要，安装必须禁用索引并强制哈希。先确认解释器/平台符合冻结wheel：当前是CPython3.12/macOS arm64，rpds-py为相应本机二进制，不支持直接搬到任意系统。不能以改包版本或安装最新版本来冒充原环境。

向全新目录执行`pip install --no-index --no-deps --require-hashes --find-links ... --requirement ... --target ...`。随后用`python -S`、只指向新目录的PYTHONPATH以及PYTHONNOUSERSITE运行检查，核对实际导入文件均来自新目录，sys.path没有旧python-libs或site-packages。这样才能确认没有靠当前已安装库补上缺包；安装仍使用当前pip/解释器，不能宣称解释器已经重建。

一次干净重建已通过题组、标注、旧尝试、新响应及已评分样本五项研究合同检查。五包wheel声明MIT、typing_extensions声明PSF-2.0，相应通知保留；没有改它们的代码，也没有据软件许可授予教材/试卷用途。此证据不替代完整分发许可审查、OCR/ASR环境、独立机器或磁盘丢失恢复。新资产仍须纳入后续保存与从保存副本实际重跑，M7继续未通过。
