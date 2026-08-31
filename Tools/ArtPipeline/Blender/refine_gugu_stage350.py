"""增加连续的围巾正面布片，生成 stage350 美术定稿。"""

from __future__ import annotations

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-340-art-final-candidate.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-350-art-final.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def delete_object(name: str) -> None:
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)


def create_scarf_front_panel() -> bpy.types.Object:
    name = "DEC_GUGU_ScarfFrontPanel"
    delete_object(name)
    points = [
        (-1.34, 3.47),
        (-0.72, 3.49),
        (0.20, 3.47),
        (1.08, 3.49),
        (1.66, 3.47),
        (1.61, 3.28),
        (1.02, 3.25),
        (0.22, 3.23),
        (-0.65, 3.25),
        (-1.29, 3.28),
    ]
    front_y = -1.545
    back_y = -1.495
    count = len(points)
    vertices = [(x, front_y, z) for x, z in points] + [(x, back_y, z) for x, z in points]
    faces: list[tuple[int, ...]] = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections["CHR_GUGU_DECALS"].objects.link(obj)
    mesh.materials.append(bpy.data.materials["MAT_GUGU_red"])
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("前布片圆角", "BEVEL")
    bevel.width = 0.038
    bevel.segments = 4
    return obj


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage350-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage340 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    create_scarf_front_panel()
    bpy.context.scene["gugu_stage"] = "art_final_350"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr_final"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage350 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
