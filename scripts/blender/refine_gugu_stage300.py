"""在保持正脸浅浮雕的前提下恢复后侧体积，生成 stage300。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-290-art-qa-candidate.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-300-volume-balanced.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage240.py"


def load_helpers():
    spec = importlib.util.spec_from_file_location("gugu_stage240_helpers", STAGE240_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载精修脚本：{STAGE240_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage300-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage290 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    helpers = load_helpers()

    # 正面 Y 边界保持不变，只向后恢复头身饱满度。
    helpers.set_world_depth(bpy.data.objects["CHR_GUGU_Head"], -1.472, 1.18)
    helpers.set_world_depth(bpy.data.objects["CHR_GUGU_Torso"], -1.198, 1.28)
    for side in ("R", "L"):
        # 翼根由前视薄片恢复为包住身体侧面的体积，前视轮廓不变。
        helpers.set_world_depth(bpy.data.objects[f"CHR_GUGU_Wing.{side}"], -1.30, 0.05)

    bpy.context.scene["gugu_stage"] = "volume_balanced_300"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage300 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
