# 咕咕 v3 Stage 420 动画资产 QA 判定

## 结论

**SHIP WITH NOTES：首批应用内动画资产可交付，可进入 App 集成与设备性能验证。**

本判定覆盖源骨架、刚性蒙皮、动作关键帧、循环接缝、关键姿态渲染、真实时间轴视频、动画 GLB 导出和空场景往返导入。当前动作库包含待机、庆祝和说话三种核心状态，尚不是完整情绪动作库。

## 动画内容

| 动作 | 源帧 | 运行时帧 | 时长 | 循环 | 用途 |
|---|---:|---:|---:|---|---|
| `GUGU_IDLE_LOOP` | 1–97 | 0–96 | 4.0s | 是 | 呼吸、轻微摆头、双翼/尾羽/围巾/挎包次级运动、两次眨眼 |
| `GUGU_CELEBRATE` | 1–73 | 0–72 | 3.0s | 否 | 下蹲预备、起跳伸展、双翼上扬、开喙、落地压缩与回弹 |
| `GUGU_TALK_LOOP` | 1–49 | 0–48 | 2.0s | 是 | 非机械等距的喙开合、轻微呼吸与摆头、一次眨眼 |

三段动作均为 24fps。待机、说话和庆祝回位的首尾渲染画面 SSIM 为 `1.0`；GLB 回读后的骨骼姿态最大首尾差值为 `0.0`。

## 骨架与蒙皮

- 骨架：`RIG_GUGU`，21 根骨骼。
- 角色网格：49 个，全部显式父级到骨架。
- 蒙皮：每个网格都有且只有一个有效 Armature 修改器。
- 权重：每个顶点恰好 1 个影响，权重为 `1.0`；最大影响数为 1。
- 源顶点：20,110。
- GLB 顶点：25,373（包含导出时应用的细分/圆角结果）。
- GLB 三角面：39,804。
- Root motion：无；适合 UI 卡片、头像和课程页固定锚点播放。

源审计：`Assets/Brand/Model/analysis/qa/stage420-rig-audit.json`，结论 `PASS`。

## 动画 GLB 往返门禁

- 文件：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-animated.glb`
- 文件大小：1,634,836 bytes。
- 网格：49 / 49。
- 骨架：1 / 1。
- 骨骼：21 / 21。
- 材质：22。
- 动作：3 / 3，名称与采样数全部一致。
- 未蒙皮网格：0。
- 缺失/额外资产节点：0。
- 空材质：0。
- 验证结论：`PASS`。

Blender glTF 导入器会创建一个位于 `glTF_not_exported` 集合中的 `Icosphere` 骨骼显示控件；它不在 GLB 节点或网格数据中，验证器已明确排除该导入辅助对象。

完整报告：`Assets/Brand/Model/analysis/qa/stage420-animated-glb-validation.json`。

## 视觉 QA

关键姿态：

- 待机呼吸：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-idle-breathe.png`
- 闭眼：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-idle-blink.png`
- 起跳预备：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-celebrate-anticipation.png`
- 空中欢呼：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-celebrate-air.png`
- 落地回弹：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-celebrate-land.png`
- 说话开喙：`Assets/Brand/Model/renders/gugu-v3/stage420-animation/gugu-stage420-talk-open.png`

视频预览：

- `Assets/Brand/Model/renders/gugu-v3/stage420-animation/videos/gugu-stage420-idle-loop.mp4`
- `Assets/Brand/Model/renders/gugu-v3/stage420-animation/videos/gugu-stage420-celebrate.mp4`
- `Assets/Brand/Model/renders/gugu-v3/stage420-animation/videos/gugu-stage420-talk-loop.mp4`

初版 stage410 的机械压眼眨眼和错误翅膀旋转均已被 stage420 替换：闭眼使用藏在头内的独立深蓝眼皮线；庆祝翅膀在抬起时向头身后方偏移，避免遮挡眼睛和脸颊。

## 预算判定

当前用于 UI 吉祥物的本地预算：GLB `< 5 MB`、骨骼 `< 64`、三角面 `< 50k`、单顶点影响 `≤ 4`。实际为 1.63 MB、21 骨、39.8k 三角面、1 个影响，全部通过。

## 已知说明

- 当前采用分件刚性蒙皮，适合夸张平移、旋转、缩放和形体压缩；复杂连续弯曲动作仍需后续局部软权重或形变键。
- Blender 的柔和三渲二灯光不会被所有 glTF 运行时完全复现，App 端仍需 NPR Shader。
- 说话动作为通用循环，不是逐音素口型；若后续需要精确配音同步，应增加音素/振幅驱动层。
- 尚待扩展：答错、思考、指向 UI、鼓励、获得奖励和睡眠待机。

## 交付文件

- 动画 Blender 母版：`Assets/Brand/Model/source/gugu-v3-stage-420-animation-refined.blend`
- 动画 GLB：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-animated.glb`
- 导出清单：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-animated.manifest.json`
- App 动作映射：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-animation-map.json`

SHA-256：

- BLEND：`13244237e4c6aa4f2aad71335c3ec6d6455a9ac4097bc08afc5d7fa98b8bf6c7`
- GLB：`24da92cc1387d2d6fc872d52e1c833ed30e516825959160db8cd44b730d73dfa`
- 导出清单：`8d9ae1708140714af3a3606e3e6b84578d1576e2f05f604c0ac527d7e4079be9`
