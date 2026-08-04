"""统一校正角色前后深度，生成 stage380 最终交付版本。"""

from __future__ import annotations

from pathlib import Path

import bpy


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-370-art-delivery.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-380-art-delivery-final.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def scale_character_depth(factor: float) -> None:
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.name.startswith(("CHR_", "ACC_", "DEC_")):
            continue
        inverse = obj.matrix_world.inverted()
        for vertex in obj.data.vertices:
            world = obj.matrix_world @ vertex.co
            world.y *= factor
            vertex.co = inverse @ world
        obj.data.update()


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage380-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage370 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    scale_character_depth(1.08)
    bpy.context.scene["gugu_stage"] = "art_delivery_final_380"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr_depth_calibrated"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage380 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
