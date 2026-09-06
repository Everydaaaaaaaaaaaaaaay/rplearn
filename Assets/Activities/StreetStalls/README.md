# 街边旧书摊 / 街角花摊

验收记录：[acceptance-v1.md](acceptance-v1.md)。其放行状态优先；不能以本文替代验收。

## 一次性前景

- `bookstall-source-v2.png`：内置 imagegen 全新生成；提示词 `bookstall-prompt-v2.md`。
  SHA256 `3476cb9c4aae9821083312eef8ffc293a3c00418be042ba0e392a457438cfaf4`。
- `flowerstall-source-v1.png`：内置 imagegen 全新生成；提示词 `flowerstall-prompt-v1.md`。
  SHA256 `ae6cbe40214b7b292cdcd53fa7b9743993994974f12442351e1b61c0e8eb20b2`。
- 两张输出实际均为 934×1684 RGBA，不假称生成器严格执行了要求尺寸。
  等比例缩为 852×1536（整数舍入小于一像素），顶部补 311 像素透明留白至 852×1847。
  不拉伸物品、不重绘、不去 UI、不借拒收图图生图。生成图没有街景或静止人物。
- 运行时 `App/Resources/ActivityScene/activity-{bookstall,flowerstall}-foreground.png`；
  保留 alpha，由同一张静态前景遮挡背景视频，书叶/花茎边缘不用手画粗多边形。
- v1 书摊书挡朝外的问题已拒收并移出仓库；提示词保留用于复盘，不能误认是当前图的提示词。

复现非生成处理（分别替换源图及目的路径）：

```sh
ffmpeg -i bookstall-source-v2.png -vf 'scale=852:1536:flags=lanczos,pad=852:1847:0:311:color=black@0' -frames:v 1 activity-bookstall-foreground.png
```

## 实拍动态与许可

- 旧书摊：BreakDownPictures / Pixabay 67850，锡比乌公共广场，59.966667 秒。
  https://pixabay.com/videos/building-houses-square-street-67850/
  https://cdn.pixabay.com/video/2021/03/12/67850-523396004_large.mp4
  源 SHA256 `158a7cd07f542f6521f82470411d54e1b7472aafbdb899e7526b9267c7787bce`。
  页面及 Pixabay Content License 已核对；不暗示人物或品牌代言。
- 花摊：Liemedia / Pixabay 18027，旧金山街角行人和车辆，63.229833 秒。
  https://pixabay.com/videos/san-francisco-crowd-usa-city-18027/
  https://cdn.pixabay.com/video/2018/09/01/18027-287831458_large.mp4
  源 SHA256 `0e6bcbb61436f739c50f945dc8cff69766da3497774e05520a161756b0a239c4`。
  页面及 https://pixabay.com/service/license-summary/ 实际核对。
  不原样出售/分发素材，不用人物作 NPC 身份或代言；裁切避开主要招牌并做远景柔焦。
- 背景是通用情景参考，不冒充用户当前驻地实拍、实时街景或真正存在的摊位。
  App 页面和素材来源页都有说明。原片不随 App 分发，仅打包加工后的背景。
- 5330911 备用片来源页无法核实且遇安全验证，未使用；未绕过验证。
- 5330825 曾试用，但 18.5 秒短循环中的绿裙路人在接缝中途淡入，G3 拒收，未作为最终素材。

## 确定性动态处理

`Scripts/prepare-neighbourhood-scenes.py` 用 OpenCV/SIFT 固定建筑作参照稳定画面，
随后裁切、离线调色和失焦，H.264 24fps，无音轨。不会占用角色语音的音频会话。

```sh
python Scripts/prepare-neighbourhood-scenes.py bookstall /path/to/67850.mp4 App/Resources/ActivityScene
python Scripts/prepare-neighbourhood-scenes.py flowerstall /path/to/18027.mp4 App/Resources/ActivityScene
```

- 书摊：原片 14–59.5 秒；先缩到 1920×1080，裁切 (850,0,780,1075)，512×706，最终 45 秒。
  排除前 14 秒靠近镜头的路人，保留多组远处正常行走、停留的路人。
- 花摊：原片 0.5–62.5 秒；裁切 (820,0,750,1080)，512×738，最终 61.5 秒。
- 最后 0.5 秒衔接开头 0.5 秒，输出从原片 0.5 秒起；文件边界接相邻时刻。
  这只能消除播放/曝光硬切，是否有人影跳变必须通过实际接缝检查，不能只看时长断言自然。
- 不定格等待、不倒放、不复制人影、不随机 seek。45/61.5 秒都是有限循环，
  不宣称无限新人物。长时间专注背景仍会发现重复，后续可替换更长同机位实拍。
- 单可见 AVQueuePlayer/AVPlayerLooper，沿用咖啡馆渲染与生命周期；不逐帧刷新 SwiftUI，
  场景隐藏/后台暂停，节能或减少动态使用同构图底板。没有新增全屏实时模糊滤镜。

## 交互及社交

沿用首页/我的的图文材质、整体平面投影、0.12 秒按压协调与快速交替隐现。
图文具体四角见 `ActivitySceneGeometry.swift`，不改变共享颜色或溢光参数。
三个场景共用历史角色池 ID，角色来源、稳定 ID 重试、复遇、联系邀请、加好友、聊天及足迹
继续走现有服务。六项新行动有各自遇见的理由、两种开场、实际回应及不强迫联系的告别分支。
不为真实视频路人生成身份；模拟器验收的隔离人物夹具不是生产 AI 内容。
