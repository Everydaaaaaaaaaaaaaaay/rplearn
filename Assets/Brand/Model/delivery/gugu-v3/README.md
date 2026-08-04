# 咕咕 v3 美术模型交付

## 当前文件

- `gugu-v3-animated.glb`：当前应用内动画交付，包含 49 个蒙皮网格、21 根骨骼和 3 个动作。
- `gugu-v3-animated.manifest.json`：动画 GLB 的网格、骨骼、动作和采样清单。
- `gugu-v3-animation-map.json`：App 事件与动作名称、循环和过渡时间映射。
- 动画 Blender 母版：`Assets/Brand/Model/source/gugu-v3-stage-420-animation-refined.blend`。
- `gugu-v3-art-final.glb`：当前开放格式美术交付，包含 47 个命名网格对象。
- `gugu-v3-art-final.manifest.json`：导出对象清单，用于 GLB 往返完整性校验。
- Blender 可编辑母版：`Assets/Brand/Model/source/gugu-v3-stage-400-art-delivery-final.blend`。
- `gugu-v3-static.glb`：旧 stage230 静态基线，仅用于历史对比，不再作为后续制作入口。

## 状态

- 美术静态母版：已通过多视图、拓扑与 GLB 往返导入验证。
- 外观：已完成动画化低浮雕脸、分层翅膀/围巾/挎包细节及柔和三渲二 Blender 母版。
- 骨骼/蒙皮：已完成 21 骨轻量骨架与 49 个分件刚性蒙皮。
- 表情/动作：已完成待机、庆祝和说话三段核心动作。
- 应用内三渲二：未烘焙为贴图，应由运行时 NPR Shader 实现。

## 关键约定

- 结构部件保持 `CHR_GUGU_*`、`ACC_GUGU_*` 与 `DEC_GUGU_*` 语义命名。
- 眼眉贴合头部曲率，脸颊为约 `0.04` 厚度的浅浮雕结构，适合卡通表情动画。
- 验证报告：`Assets/Brand/Model/analysis/QA_VERDICT_STAGE400.md`。
- 动画验证报告：`Assets/Brand/Model/analysis/QA_VERDICT_STAGE420_ANIMATION.md`。

## 完整性

- `gugu-v3-art-final.glb`：`c4edc3f1c9f6b9fc62bd851b83b2b48bd29534224f8f5dc66f66607887b47a07`
- `gugu-v3-stage-400-art-delivery-final.blend`：`5f9fa78d9e6f8ecbc98ea3b1b974cfe7c01c8d1ba2c85cbbba57df769e57bab8`
- `gugu-v3-animated.glb`：`24da92cc1387d2d6fc872d52e1c833ed30e516825959160db8cd44b730d73dfa`
- `gugu-v3-stage-420-animation-refined.blend`：`13244237e4c6aa4f2aad71335c3ec6d6455a9ac4097bc08afc5d7fa98b8bf6c7`
