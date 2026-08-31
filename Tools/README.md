# 离线工具

这些工具不参与 App 或后端运行时构建。日常开发从仓库根目录执行，工具通过自身路径推导仓库根，不依赖某台机器的绝对路径。

- `ArtPipeline/artasset.mjs`：图片裁切、尺寸处理、清单检查与精灵图生成。
- `ArtPipeline/Blender/`：吉祥物模型分析、拟合、绑定、导出和验证流水线。
- `Dictionary/build_dictionary.py`：将 ECDICT CSV 构建为 App 随包 SQLite 词典。

开始美术任务时先读 `Assets/Brand/asset-manifest.json`、相邻 report 或交付目录 README；不要通过遍历渲染产物来理解流水线。
