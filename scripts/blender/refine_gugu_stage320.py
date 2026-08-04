"""修复侧羽跨视图穿帮与包带层级，生成 stage320。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-310-wing-depth-refined.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-320-crossview-clean.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage240.py"


def load_helpers():
    spec = importlib.util.spec_from_file_location("gugu_stage240_helpers", STAGE240_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载精修脚本：{STAGE240_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def move_mesh_world_x(obj: bpy.types.Object, offset: float) -> None:
    inverse = obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        world.x += offset
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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage320-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage310 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    helpers = load_helpers()

    for name in ("DEC_GUGU_WingSideLayer.L.1", "DEC_GUGU_WingSideLayer.L.2"):
        move_mesh_world_x(bpy.data.objects[name], -0.115)
    for name in ("DEC_GUGU_WingSideLayer.R.1", "DEC_GUGU_WingSideLayer.R.2"):
        move_mesh_world_x(bpy.data.objects[name], 0.115)
    bpy.data.objects["DEC_GUGU_WingSideGroove.L"].data.transform(Matrix.Translation((-0.16, 0.0, 0.0)))
    bpy.data.objects["DEC_GUGU_WingSideGroove.R"].data.transform(Matrix.Translation((0.16, 0.0, 0.0)))

    # 腹部花色只负责贴体，包带必须位于它的前方。
    helpers.set_world_depth(bpy.data.objects["ACC_GUGU_Satchel_Strap"], -1.70, -1.62)

    bpy.context.scene["gugu_stage"] = "crossview_clean_320"
    bpy.context.scene["art_direction"] = "flat_face_full_body_crossview_wings"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage320 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
