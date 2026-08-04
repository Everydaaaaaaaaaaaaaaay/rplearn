# 咕咕 v3 Stage 400 美术交付判定

## 结论

**SHIP WITH NOTES：美术静态母版可交付，并可进入绑定与动画阶段。**

本判定覆盖角色一级形体、低浮雕动画脸、柔和三渲二外观、正/侧/背轮廓、四视角成片、命名结构、网格完整性，以及 GLB 导出后的空场景往返导入。当前文件尚未制作骨骼、蒙皮、表情形变键或动作，因此本结论不等于“应用内动画资产已完成”。

## 美术完成项

- 头身比例从基础球体堆叠调整为更明确的动画角色轮廓。
- 眼睛与眉毛贴合头部曲率，脸颊压缩为约 `0.04` 厚度的低浮雕面片；正面保持平面动画感，侧面不再出现悬空硬片。
- 喙拆分上下两层，保留适合后续开合动画的结构。
- 翅膀增加主羽轮廓、正面分层与侧向贴合羽片，避免单一胶囊体观感。
- 围巾重做为分层软布带，清理多余底环，并保留独立结与双尾。
- 挎包重做为包身、翻盖、背带、扣环、纽扣和缝线的可读结构。
- 脚掌改为软轮廓，并增加可导出的趾沟网格。
- 使用柔和三渲二材质、低反差阴影和轮廓色层级；没有依赖私有贴图格式。

## 多视图门禁

| 视角 | IoU | 参考 bbox | 模型 bbox | 判定 |
|---|---:|---|---|---|
| 正面 | 0.8929 | `[52,149,435,571]` | `[50,154,435,566]` | 通过；主体尺寸基本一致 |
| 侧面 | 0.7975 | `[90,149,343,574]` | `[100,153,340,570]` | 有说明通过；厚度与重心仍有约 10 px 偏差，但美术侧视连续且无遮挡错误 |
| 背面 | 0.8885 | `[32,154,450,564]` | `[59,158,432,561]` | 通过；主体高度与重心稳定 |

三视图平均 IoU：`0.8596`。数据来自清理后的完整角色参考掩码，不使用带有相邻视图残片的原始图。

成片：

- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage400-front.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage400-three_quarter.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage400-side.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage400-back.png`

完整拟合数据：`Assets/Brand/Model/analysis/fit/stage400-clean/fit-summary.json`。

## 网格与结构门禁

- 结构部件：`28 / 28`。
- 角色网格对象：`47`。
- Blender 材质：`25`。
- 顶点：`19,410`。
- 面：`20,257`。
- 非流形/开放边：`0`。
- 松散点/松散边：`0`。
- 退化面：`0`。
- 负缩放：`0`。
- 空材质槽：`0`。
- 骨骼：未制作。

完整机器审计：`Assets/Brand/Model/analysis/qa/stage400-model-audit.json`。

## GLB 往返验证

- 47 个导出网格与清单逐对象一致。
- 22 个 GLB 材质均可重新导入。
- 无缺失结构部件、清单外部件、空材质或零厚度对象。
- 文件大小：`1,306,948 bytes`。
- 验证结论：`PASS`。

验证数据：`Assets/Brand/Model/analysis/qa/stage400-glb-validation.json`。

Blender 母版中的柔和三渲二灯光与节点效果不会由所有 glTF 运行时逐项复现；GLB 保留了开放格式网格、命名和基础材质，应用内最终外观应由运行时 NPR Shader 接管，而不是烘焙成纯美术贴图。

## 交付文件

- Blender 美术母版：`Assets/Brand/Model/source/gugu-v3-stage-400-art-delivery-final.blend`
- 开放格式模型：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-art-final.glb`
- 导出对象清单：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-art-final.manifest.json`

SHA-256：

- BLEND：`5f9fa78d9e6f8ecbc98ea3b1b974cfe7c01c8d1ba2c85cbbba57df769e57bab8`
- GLB：`c4edc3f1c9f6b9fc62bd851b83b2b48bd29534224f8f5dc66f66607887b47a07`
- 清单：`2ce7bca4a8b252f6c6e385e36c56cfdfd7a1bd234a3d90320aba6419f23de`

## 下一阶段边界

后续应以本母版为唯一基线，依次完成骨骼与蒙皮、眼眉/喙/翅膀控制器、表情形变键、待机与反馈动作、应用内 NPR Shader、动画状态机和设备性能验证。旧的 stage230 文件只作为历史基线保留。
