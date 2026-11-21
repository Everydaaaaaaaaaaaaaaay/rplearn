# 城市地点实拍候选

新版活动使用与地点一致的当地实拍。`candidates.json` 保存 Commons 来源页、作者、许可、描述、下载地址、尺寸、处理与哈希；它记录搜索候选，不构成地理或视觉验收通过。

下载与候选预览缓存在 `build/ActivityWorldPhotos/`。只有人工核对城市、地点、画面空间、许可条件，并检查原生裁切后，才将选中照片加入正式内容清单和 App 资源。缺图的地点不使用异地照片或生成图冒充。

从仓库根运行 `python3 Tools/ContentPipeline/activity-place-photos.py --city london --city newyork --city nairobi` 获取三城候选；不指定城市时获取全部。脚本不修改正式世界清单，不自动给出通过结论。

本轮检索覆盖 46 处，40 处有候选，另 8 处尚未完成检索；这些数字不表示合格图片数。Commons 对部分请求返回 429 后已停止本轮获取；后续使用单线程、全局至少三秒间隔和服务端要求的冷却，按缺口定向补查。保留已有来源与审校记录，搜索失败不清空旧候选。PDF、SVG 等缩略图不作为照片候选。

独立原生样板的三张选图另见 [preview-photos.json](preview-photos.json) 及 [验收边界](acceptance-preview-v1.md)。图库中的店铺、街道和市场名称仍需逐项核实；例如市中心 Java House 不能当作内罗毕 Westlands 咖啡馆，Union Square 的版画不能当作市场实拍。
