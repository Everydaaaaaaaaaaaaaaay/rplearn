# 十五城相遇过渡影像

施工要求见 `docs/activity-encounter-journey-plan.md`，最新来源阶段验收见 `acceptance-v2.md`（功能验证保留于 `acceptance-v1.md`）。
此目录保存来源、许可、选段与审核证据；原始大文件暂存 build/EncounterJourney，不进入App。
只有逐城地点、免费应用使用许可、原生>=59.94fps（59.94按60播放）及运动/清晰度通过后才安装运行视频。
输出契约：App/Resources/ActivityScene/encounter-journey.mp4，900帧/60fps/15秒，无音轨；
encounter-journey.json 包含 movie（不含扩展名）和按原片顺序的15个城市ID。
运行时通过同一源片的两个连续区间调整起点，以当前城市为最后1秒。
缺少该契约时运行安静底色，属于功能降级，不是影像交付。

帧率补充（用户确认）：允许60000/1001fps原片保留每帧、按60fps播放，约加快0.1%；不插帧、不复制帧。

扩展搜寻见 `search-notes-v2.md`；两城技术清单 `candidates-v3.json`，带署名的候选预览位于 `previews-v2/`。金斯敦仍为备选，未安装运行影片。
