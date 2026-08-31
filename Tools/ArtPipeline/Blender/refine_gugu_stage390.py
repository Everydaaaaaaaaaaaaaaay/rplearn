"""将面部部件贴合头部曲面，生成 stage390 低浮雕动画脸版本。"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-380-art-delivery-final.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-390-art-delivery-final.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def project_face_part_to_head(
    object_name: str,
    front_offset: float,
    back_offset: float,
) -> None:
    """保持正面轮廓与层级顺序，将部件沿 Y 轴贴到头部表面。"""
    obj = bpy.data.objects[object_name]
    head = bpy.data.objects["CHR_GUGU_Head"]
    obj_inverse = obj.matrix_world.inverted()
    head_inverse = head.matrix_world.inverted()

    world_vertices = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    min_y = min(vertex.y for vertex in world_vertices)
    max_y = max(vertex.y for vertex in world_vertices)
    depth = max(max_y - min_y, 1e-8)

    for vertex, world in zip(obj.data.vertices, world_vertices):
        layer_ratio = (world.y - min_y) / depth
        ray_origin = Vector((world.x, -10.0, world.z))
        ray_direction = Vector((0.0, 1.0, 0.0))
        hit, location, _normal, _face = head.ray_cast(
            head_inverse @ ray_origin,
            (head_inverse.to_3x3() @ ray_direction).normalized(),
        )
        if not hit:
            continue
        surface = head.matrix_world @ location
        offset = front_offset + (back_offset - front_offset) * layer_ratio
        world.y = surface.y - offset
        vertex.co = obj_inverse @ world

    obj.data.update()


def refine_flat_face() -> None:
    # 眼球内部的材质层级仍由原始 Y 顺序决定，但整体像贴花一样服从头部曲率。
    for name in ("CHR_GUGU_Eye.R", "CHR_GUGU_Eye.L"):
        project_face_part_to_head(name, front_offset=0.035, back_offset=0.008)

    for name in ("CHR_GUGU_Brow.R", "CHR_GUGU_Brow.L"):
        project_face_part_to_head(name, front_offset=0.018, back_offset=0.006)

    for name in ("CHR_GUGU_CheekPad.R", "CHR_GUGU_CheekPad.L"):
        project_face_part_to_head(name, front_offset=0.045, back_offset=0.006)


def render_views() -> None:
    scene = bpy.context.scene
    cameras = {
        "front": bpy.data.objects["CAM_验证_正面"],
        "side": bpy.data.objects["CAM_验证_侧面"],
        "back": bpy.data.objects["CAM_验证_背面"],
        "three_quarter": bpy.data.objects["CAM_验证_四分之三"],
    }
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    for role, camera in cameras.items():
        scene.camera = camera
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage390-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage380 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    refine_flat_face()
    bpy.context.scene["gugu_stage"] = "art_delivery_final_390"
    bpy.context.scene["art_direction"] = "conformal_low_relief_face_soft_npr"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage390 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
