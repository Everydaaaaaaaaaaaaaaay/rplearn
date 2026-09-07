# 街角咖啡馆 · 社交试点

**已被v4替代**：用户同意环境动态后，当前运行场景为完整外摆咖啡馆照片加局部树影，
见[新素材及实现](../Ambient-v4/README.md)和[验收记录](../StreetStalls/acceptance-v4.md)。
下文为已拒收v3的历史实现；旧资源已移至`../RejectedRuntime-v3/`，不再打包或播放。

当前视觉状态：2026-09-07用户复查退回。v3已局部修复入口压扁/过小，室内外机位及循环问题仍未关闭。
本文保留实现说明，不是放行证据；以[最新检查记录](../StreetStalls/acceptance-v3.md)为准。

## 来源与许可

- 当前室内母版：`interior-source-v2.png`，内置 imagegen 独立一次生成，实际853×1844。
  完整提示词 `foreground-prompt-v2.md`；未使用旧图作图生图输入。
  原 `interior-source.png` 因直立道具像无用途的书、书籍重复而撤销视觉通过，留作历史证据。
  本轮实拍参照与验收：[acceptance-v2.md](../StreetStalls/acceptance-v2.md)。
- 街景：Davide Giordani / Pixabay 27023，London, building, people（61.019 秒）。
  https://pixabay.com/videos/london-building-people-walking-27023/
  实际源：https://cdn.pixabay.com/video/2019/09/19/27023-361798579_large.mp4
  页面明确列出 Pixabay Content License；许可：https://pixabay.com/service/license-summary/ 。
  不单独转售素材，不暗示路人代言或把真实路人当作 AI 角色。
  源 SHA256 `7bc6141956c1e72e2b39e7d96829cb6fb02855b75ee1eb4607d41885d47a501a`。
- 原片只在素材处理缓存，不随 App 或独立图库分发。App 内是处理后的情景背景，
  并明确标注非当前城市实拍 / 实时画面。视频人物不作为 NPC 身份或头像。

## 确定性处理与平面标注

处理环境：Python + opencv-python-headless / numpy、ffmpeg。

```sh
python Scripts/stabilize-cafe-footage.py <27023.mp4> /tmp/cafe-stabilized.mp4
bash Scripts/prepare-cafe-activity-scene.sh --rejected-preview /tmp/cafe-stabilized.mp4 /tmp/cafe-rejected-preview
```

室内运行时 PNG 与新母版字节一致，未二次生成、未放大。原视频取 13.5–60.5 秒，以建筑
特征匹配进行离线平面配准，排除路人、旗帜和天空；统一参考画面中裁切
x=400,y=40,w=1300,h=1040，缩为650×520中间文件，再取底部650×404匹配新窗户。
当前实现用底部对齐保留街道路面，但用户复查指出近处人物可见范围/贴地机位不合理；
此裁切不能当作正确眼高的依据，待按S1重新审查。不能拉扁人物。
24fps H.264，无音轨。
接缝只在无近景身体的区间，用 0.5 秒衔接远处运动/曝光；把衔接段移至末尾，
得到 46.5 秒闭环。最后一帧之后接的是相邻时刻，不重复一段静止底板。

窗口四角（852×1847标定坐标）：TL(82,340)、TR(827,340)、BR(822,803)、BL(84,803)。
静态底板与视频使用同一投影，新图没有跨窗物件，不再保留旧菜单遮罩。
三个入口分别关联窗边、杯身和点心盘旁桌面，复用原来的整体图文 homography。

## 动态的实际能力与边界

- 旧方案的三段短事件与 12–30 秒定格等待已经撤下；这不是自然空场，而是冻结世界。
- 新版本保持多组不同路人、远处交通与背景运动的真实时序；即使近处无人，也持续
  解码原片，不暂停、不倒放、不变速、不镜像或复制人物。
- 一个 AVQueuePlayer / AVPlayerLayer，由 AVPlayerLooper 提前排入下一副本；不在
  播完回调中重新加载/seek，不运行随机停顿计时器。生产无逐帧 SwiftUI 更新。
- 可见对话不会暂停窗外；切离页面、后台、覆盖的足迹页暂停。手动静态、减少动态、
  低电量、高温与失败保持原有降级，不抢语音的音频会话。
- 明确边界：这仍是 **46.5 秒有限实拍循环**，不是无限新人物或随机世界模拟。
  本次优先保证连续性和多位人物自然经过，不用任意跳片制造假随机或瞬移。
  很长时间注视仍能识别重复；若需要更长的无重复观察窗口，需追加同机位长素材。
- 减少透明度时对话面板实底；大字模式用可读替代入口。没有修改共享材质参数。

## 社交闭环

窗边「聊聊附近」、杯子「共用一桌」、点心旁「聊聊口味」。
旧 `cafe-book` 足迹保留原题目，新增 `cafe-taste`，不拿旧ID改写历史。
本机同城未移除角色可合理
复遇（25% 概率尝试，24 小时交流间隔）；公共库共用 `social-cafe-v1`，不是每个按钮创建独立空池。新人物只在需要时
生成，模板失败不冒充 AI 新人；同次重试保存稳定 ID。暂缺公共头像保持待补状态。
角色短句按身份和实际选择生成，控制在 28 词、180 字符内；不为用户配音。
每条实际呈现的交流和情景记忆幂等保存到同一人物，再由 App 组装继续聊天。
联系邀请允许拒绝，拒绝/告别没有新增好友按钮。好友位满不删除或重置现有关系。

验收结果与未来范围以 `docs/city-activities-social-pilot-plan.md` 为准。
