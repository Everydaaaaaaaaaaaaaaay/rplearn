"""消除前视沟线在侧视图中的悬浮，生成 stage290 QA 候选。"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Matrix


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-280-character-detail.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-290-art-qa-candidate.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def move_curve_data_y(name: str, offset: float) -> None:
    obj = bpy.data.objects.get(name)
    if obj is None or obj.type != "CURVE":
        return
    obj.data.transform(Matrix.Translation((0.0, offset, 0.0)))
    obj.data.update_tag()


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage290-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage280 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    move_curve_data_y("DEC_GUGU_Satchel_Seam", 0.075)
    for side in ("R", "L"):
        move_curve_data_y(f"DEC_GUGU_ToeGroove.{side}.1", 0.035)
        move_curve_data_y(f"DEC_GUGU_ToeGroove.{side}.2", 0.035)
    bpy.context.scene["gugu_stage"] = "art_qa_candidate_290"
    bpy.context.scene["art_direction"] = "animation_soft_npr_qa_candidate"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage290 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
