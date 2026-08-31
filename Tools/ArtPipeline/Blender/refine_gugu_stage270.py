"""修复 stage260 的围巾侧影与脚部体积，生成 stage270。"""

from __future__ import annotations

import math
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-260-shape-polished.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-270-silhouette-refined.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def delete_object(name: str) -> None:
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)


def create_layered_scarf() -> bpy.types.Object:
    """三层扁布环共同形成围巾，不使用圆管截面。"""
    segments = 96
    center_x = 0.21
    band_specs = [
        # 中心 Z、X 半径、Y 半径、径向厚度、半高、材质槽。
        (3.18, 1.50, 1.36, 0.13, 0.105, 1),
        (3.35, 1.54, 1.38, 0.13, 0.115, 0),
        (3.52, 1.50, 1.35, 0.13, 0.105, 2),
    ]
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    face_materials: list[int] = []
    for band_index, (center_z, radius_x, radius_y, radial_half, vertical_half, material_index) in enumerate(band_specs):
        start = len(vertices)
        for index in range(segments):
            angle = math.tau * index / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            # 极小的上下起伏使布料环不呈机械水平线。
            wave = 0.012 * math.sin(angle * 2.0 + band_index * 0.85)
            center = (center_x + radius_x * cosine, radius_y * sine, center_z + wave)
            radial = (cosine, sine)
            vertices.extend(
                [
                    (center[0] + radial[0] * radial_half, center[1] + radial[1] * radial_half, center[2] + vertical_half),
                    (center[0] - radial[0] * radial_half, center[1] - radial[1] * radial_half, center[2] + vertical_half),
                    (center[0] - radial[0] * radial_half, center[1] - radial[1] * radial_half, center[2] - vertical_half),
                    (center[0] + radial[0] * radial_half, center[1] + radial[1] * radial_half, center[2] - vertical_half),
                ]
            )
        for index in range(segments):
            following = (index + 1) % segments
            current = start + index * 4
            nxt = start + following * 4
            faces.extend(
                [
                    (current, nxt, nxt + 1, current + 1),
                    (current + 1, nxt + 1, nxt + 2, current + 2),
                    (current + 2, nxt + 2, nxt + 3, current + 3),
                    (current + 3, nxt + 3, nxt, current),
                ]
            )
            face_materials.extend([material_index] * 4)
    mesh = bpy.data.meshes.new("ACC_GUGU_Scarf_Wrap_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("ACC_GUGU_Scarf_Wrap", mesh)
    bpy.data.collections["CHR_GUGU_ACCESSORIES"].objects.link(obj)
    mesh.materials.append(bpy.data.materials["MAT_GUGU_red"])
    mesh.materials.append(bpy.data.materials["MAT_GUGU_red_shadow"])
    mesh.materials.append(bpy.data.materials["MAT_GUGU_red_light"])
    for polygon, material_index in zip(mesh.polygons, face_materials):
        polygon.material_index = material_index
        polygon.use_smooth = True
    bevel = obj.modifiers.new("布带圆角", "BEVEL")
    bevel.width = 0.045
    bevel.segments = 3
    return obj


def rebuild_scarf() -> None:
    delete_object("ACC_GUGU_Scarf_Wrap")
    delete_object("DEC_GUGU_ScarfFold_Dark")
    delete_object("DEC_GUGU_ScarfFold_Light")
    create_layered_scarf()

    # 结位于后侧布环末端，飘带从结向外展开。
    knot = bpy.data.objects["ACC_GUGU_Scarf_Knot"]
    knot.data.transform(__import__("mathutils").Matrix.Translation((0.0, 0.75, 0.0)))
    for name in ("ACC_GUGU_Scarf_Tail_A", "ACC_GUGU_Scarf_Tail_B"):
        obj = bpy.data.objects[name]
        obj.data.transform(__import__("mathutils").Matrix.Translation((0.0, 0.55, 0.0)))


def foot_outline(center_x: float) -> list[tuple[float, float]]:
    relative = [
        (-0.49, 0.075),
        (-0.51, 0.14),
        (-0.45, 0.205),
        (-0.34, 0.225),
        (-0.28, 0.285),
        (-0.17, 0.305),
        (-0.07, 0.25),
        (0.02, 0.305),
        (0.13, 0.315),
        (0.21, 0.255),
        (0.30, 0.285),
        (0.41, 0.27),
        (0.49, 0.205),
        (0.48, 0.13),
        (0.38, 0.075),
        (0.18, 0.05),
        (-0.05, 0.06),
        (-0.29, 0.045),
    ]
    return [(center_x + x, z) for x, z in relative]


def create_rounded_foot(name: str, center_x: float) -> bpy.types.Object:
    """以多截面放样得到正面三趾、侧面圆润的脚掌。"""
    contour = foot_outline(center_x)
    contour_center_z = 0.16
    rings = [
        (-0.66, 0.56, -0.015),
        (-0.48, 0.90, 0.012),
        (-0.20, 1.00, 0.020),
        (0.04, 0.88, 0.005),
        (0.16, 0.52, -0.020),
    ]
    count = len(contour)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for y, scale, z_offset in rings:
        for x, z in contour:
            vertices.append(
                (
                    center_x + (x - center_x) * scale,
                    y,
                    contour_center_z + (z - contour_center_z) * scale + z_offset,
                )
            )
    for ring_index in range(len(rings) - 1):
        start = ring_index * count
        following_start = (ring_index + 1) * count
        for index in range(count):
            following = (index + 1) % count
            faces.append((start + index, start + following, following_start + following, following_start + index))
    faces.append(tuple(reversed(range(count))))
    back_start = (len(rings) - 1) * count
    faces.append(tuple(back_start + index for index in range(count)))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections["CHR_GUGU_GEO"].objects.link(obj)
    mesh.materials.append(bpy.data.materials["MAT_GUGU_orange"])
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    subdivision = obj.modifiers.new("脚掌柔化", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = 1
    subdivision.render_levels = 2
    return obj


def rebuild_feet() -> None:
    for name, center_x in (("CHR_GUGU_Foot.R", -0.69), ("CHR_GUGU_Foot.L", 0.87)):
        delete_object(name)
        create_rounded_foot(name, center_x)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage270-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage260 基线：{BASELINE_BLEND}")
    if Path(bpy.data.filepath) != BASELINE_BLEND:
        bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    rebuild_scarf()
    rebuild_feet()
    bpy.context.scene["gugu_stage"] = "silhouette_refined_270"
    bpy.context.scene["art_direction"] = "animation_soft_npr_layered_cloth"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage270 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
