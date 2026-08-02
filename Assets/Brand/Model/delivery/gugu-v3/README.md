# 咕咕 v3 静态模型交付

## 文件

- `gugu-v3-static.glb`：开放的 glTF 2.0 二进制交换格式，包含 38 个命名网格对象与材质。
- Blender 可编辑源文件位于 `Assets/Brand/Model/source/gugu-v3-stage-230-delivery-final.blend`。

## 状态

- 静态模型：已通过多视图、拓扑与 GLB 往返导入验证。
- 骨骼/蒙皮：未制作。
- 表情/动作：未制作。
- 三渲二：未烘焙进 GLB，建议作为后续独立材质/渲染层实现。

## 关键约定

- 结构部件保持 `CHR_GUGU_*` 与 `ACC_GUGU_*` 语义命名。
- 脸部为浅浮雕 2.5D 分层结构，适合卡通表情动画。
- 验证报告：`Assets/Brand/Model/analysis/QA_VERDICT_STAGE230.md`。

## 完整性

`gugu-v3-static.glb` SHA-256：`5d2af256cd22c3ad0f08920f72631a0c8f2e05056c5430636cb3fc3dc19fa59d`
