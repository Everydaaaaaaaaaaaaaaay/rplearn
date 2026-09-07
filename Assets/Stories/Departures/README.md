# 出发之后制作资产

`production.json` 是来源、身份参考、实际动作观察、局部 alpha 修整与逐节点使用的清单。`raw/` 保留生成原件；正式运行文件在 `App/Resources/StoryArt/Departures/`。`reference-only`、`rejected`、`superseded` 不应打包进 App。

## 生成与处理

图片由内置 image_gen 分别生成。参考母版锁定人物身份，动作按具体台词、视线对象、手势、道具和场景设计。用户已明确允许本地抠图、优化与验收。纸张、眼白、银发不能靠全图按颜色去背景；发生误抠除时只按已测量区域恢复原始像素。

1. `swiftc Scripts/prepare-story-sprite.swift -o build/art-tools/prepare-story-sprite` 编译本机 Vision 工具（先建立输出目录）。
2. `python3 Scripts/import-departures-art.py <生成记录数组.json> --extract` 导入原件、提取 alpha 或输出 JPEG。不会自动批准图片。
3. `python3 Scripts/refine-departures-alpha.py` 重放清单记录的局部修整。不会重绘身份或改变原件。
4. `python3 Scripts/review-departures-art.py` 生成全部原件对照、深浅底透明图、逐节点与独立镜头拼图、使用清单。包含伦敦旧批次，不能只检查最后生成的一批。

Python 工具依赖 Pillow、numpy；Vision 工具需要 macOS。脚本输出为制作辅助，不是审美判断器。每次新增或修改立绘后检查动作、透明边缘与实际剧情合成；没有变化的历史素材不用反复生成。

`art-reviewed` 仅代表已记录的美术检查，不等于生产发布、商店审核或用户最终满意。正式验收证据见 `docs/verification/departures-art.md`。
