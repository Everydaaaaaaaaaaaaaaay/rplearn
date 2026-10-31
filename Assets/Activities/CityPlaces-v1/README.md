# 城市地点实拍候选

新版活动使用与地点一致的当地实拍。`candidates.json` 保存 Commons 来源页、作者、许可、描述、下载地址、尺寸、处理与哈希；它记录搜索候选，不构成地理或视觉验收通过。

下载与候选预览缓存在 `build/ActivityWorldPhotos/`。只有人工核对城市、地点、画面空间、许可条件，并检查原生裁切后，才将选中照片加入正式内容清单和 App 资源。缺图的地点不使用异地照片或生成图冒充。

从仓库根运行 `python3 Tools/ContentPipeline/activity-place-photos.py --city london --city newyork --city nairobi` 获取三城候选；不指定城市时获取全部。脚本不修改正式世界清单，不自动给出通过结论。
