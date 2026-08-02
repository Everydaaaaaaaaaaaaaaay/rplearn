# 咕咕 v3 Stage 230 QA 判定

## 结论

**SHIP：静态模型可交付。**

本判定覆盖参考图配准、正/侧/背轮廓、四视角成片、结构部件、网格完整性、材质槽与 GLB 往返导入。当前文件未包含骨骼、蒙皮、表情形变或动画，因此不能将本结论扩展为“动画资产已完成”。

## 视觉与多视图门禁

| 视角 | IoU | 参考 bbox | 模型 bbox | 结论 |
|---|---:|---|---|---|
| 正面 | 0.9013 | `[52,149,435,571]` | `[51,150,435,572]` | 通过；宽度精确一致 |
| 侧面 | 0.8886 | `[90,149,343,574]` | `[76,150,348,572]` | 通过；IoU 高于 0.82 门槛 |
| 背面 | 0.8822 | `[32,154,450,564]` | `[54,150,435,572]` | 通过；宽度误差约 3.3% |

成片：

- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage230-front.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage230-side.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage230-back.png`
- `Assets/Brand/Model/renders/gugu-v3/gugu-v3-stage230-three_quarter.png`

验证数据与叠加图位于 `Assets/Brand/Model/analysis/fit/stage230/`。

## 网格与结构门禁

- 结构部件：28 / 28。
- 角色网格对象：38。
- Blender 材质：12。
- 顶点：26,932。
- 面：28,316。
- 非流形/开口边：0。
- 松散点：0。
- 退化面：0。
- 负缩放：0。
- 空材质槽：0。

完整机器审计：`Assets/Brand/Model/analysis/qa/stage230-model-audit.json`。

## 动画方向判定

脸部采用适合卡通动画的 2.5D 结构：头壳承担整体体积；眼圈、眼白、虹膜、瞳孔和高光是低厚度分层面；脸颊是浅浮雕软面；喙保持独立前凸。该结构适合后续制作眨眼、视线、眉毛、喙开合和脸颊挤压，不依赖写实面部雕刻。

三渲二/NPR 应作为独立外观层实现，不应破坏当前 PBR 材质、语义部件或绑定结构。

## 交付文件

- Blender 源文件：`Assets/Brand/Model/source/gugu-v3-stage-230-delivery-final.blend`
- 开放格式：`Assets/Brand/Model/delivery/gugu-v3/gugu-v3-static.glb`
- GLB 往返导入验证：`Assets/Brand/Model/analysis/qa/stage230-glb-validation.json`

SHA-256：

- BLEND：`0ed1cb40a80dbac1035a4ecee97cfbeedb859a0204e8b0c31e7301d5fff782cb`
- GLB：`5d2af256cd22c3ad0f08920f72631a0c8f2e05056c5430636cb3fc3dc19fa59d`

## 后续范围

静态模型之后的独立阶段为：骨骼与蒙皮、脸部控制器/形变键、动作集、三渲二材质与应用内运行时集成。当前场景 `has_armature=false`，未把这些未完成工作计入静态模型 SHIP 结论。
