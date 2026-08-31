"""移除围巾多余底层布环，生成 stage360 最终美术版本。"""

from __future__ import annotations

from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-340-art-final-candidate.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-360-art-final.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def remove_bottom_scarf_band() -> None:
    scarf = bpy.data.objects["ACC_GUGU_Scarf_Wrap"]
    mesh = scarf.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    # stage270 的三层布环按底、中、顶顺序各占 96×4 个顶点。
    bottom_band = [vertex for vertex in bm.verts if vertex.index < 96 * 4]
    bmesh.ops.delete(bm, geom=bottom_band, context="VERTS")
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage360-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage340 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    remove_bottom_scarf_band()
    bpy.context.scene["gugu_stage"] = "art_final_360"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr_final"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage360 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
