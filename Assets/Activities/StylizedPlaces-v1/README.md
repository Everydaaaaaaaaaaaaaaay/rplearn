# 出去走走 · 风格化实拍场景 v1

2026-11-23。十五城 54 个活动地点的“活照片”场景，替换此前的程序化卡通地点（赴约地点等没有实拍的场景仍用卡通）。
来源是 [CityPlaces-v2](../CityPlaces-v2/README.md) 已验收的 54 张当地实拍，作者、许可与来源见其
[selected-photos.json](../CityPlaces-v2/selected-photos.json)；App 地点浏览页右上角菜单的“照片信息”逐图展示。
CC BY-SA 照片的风格化衍生图沿用原许可。

## 产物

逐图来源路径、指纹与天空/树叶/水面占比见 [manifest.json](manifest.json)。

`App/Resources/StylizedPlaces/`，每个地点两张：

- `styled-place-<id>.webp`：1242×2548 竖版，天空抠成透明（室内场景不透明），WebP q84。
- `styled-place-<id>-motion.png`：310×637 动态遮罩，R=树叶、G=水面、B=远近（1 为最近）。

## 处理

`Tools/ContentPipeline/stylize-place-scenes.py`，全部确定性：

1. 按 `App/Resources/activity-photo-framing.json` 的取景对齐裁成竖版。
2. SegFormer-B5（ADE20K）语义分割取天空、树叶、水面概率；DPT-Hybrid 单目深度分三块估计后按重叠区对齐。
   两个模型只做分析，不生成或修补任何像素。
3. 天空遮罩：分割结果二值化，悬空碎块（原照片的云团）并入天空、地面零星小块去掉；树冠缝隙按天空颜色补抠；
   贴着树冠或楼顶的云块（颜色像天空、深度与天空相同、与天空连通）归入天空。只在边界几像素内按照片边缘软过渡，
   半透明边缘去掉原天空颜色。
4. 曝光与白平衡统一，三遍双边滤波加保边平滑，40 色色阶归并后以 30% 与平滑结果混合，插画调色（暗部偏蓝紫、
   亮部偏暖），XDoG 细描线（只描梯度足够的边、去掉孤立小点，树叶、水面减弱），远处轻微空气透视，亮处柔光，轻锐化。

App 端（`PuffPlacePhotoScene`）在背后画按当地时间变化的天空与柔边云，着色器 `puffLivingPhoto`
按遮罩让树叶摇、水面起波并零星泛起柔和波光，镜头缓慢漂移形成视差；黄昏偏暖、夜里室外偏蓝变暗、室内只略压暗；
减弱动态效果时静止。

## 复现

```sh
HF_HOME=build/agent-tmp/hf python3 Tools/ContentPipeline/stylize-place-scenes.py            # 全部地点
HF_HOME=build/agent-tmp/hf python3 Tools/ContentPipeline/stylize-place-scenes.py london-southbank --out /tmp/x --preview /tmp/x-preview
```

依赖 torch、transformers（4.36）、opencv-python、Pillow；首次运行会下载两个模型到 `HF_HOME`。

验收记录见 [acceptance-v1.md](acceptance-v1.md)。
