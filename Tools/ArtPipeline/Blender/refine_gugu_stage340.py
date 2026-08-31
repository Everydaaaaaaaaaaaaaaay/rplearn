"""收口翼羽图形与围巾层级，生成 stage340 美术定稿候选。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-330-wing-surface-fitted.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-340-art-final-candidate.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "Tools/ArtPipeline/Blender/refine_gugu_stage240.py"


def load_helpers():
    spec = importlib.util.spec_from_file_location("gugu_stage240_helpers", STAGE240_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载精修脚本：{STAGE240_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def delete_object(name: str) -> None:
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage340-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage330 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    helpers = load_helpers()
    delete_object("DEC_GUGU_WingSideGroove.L")
    delete_object("DEC_GUGU_WingSideGroove.R")
    # 花色贴体但位于三层围巾之后，避免胸口露出孤立红色椭圆。
    helpers.set_world_depth(bpy.data.objects["DEC_GUGU_BellyPatch"], -1.48, -1.23)
    bpy.context.scene["gugu_stage"] = "art_final_candidate_340"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr_final_candidate"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage340 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
