"""恢复前胸体积并为翅膀增加真正的侧向羽片，生成 stage310。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-300-volume-balanced.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-310-wing-depth-refined.blend"
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


def create_side_panel(
    name: str,
    yz_points: list[tuple[float, float]],
    front_x: float,
    back_x: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    count = len(yz_points)
    vertices = [(front_x, y, z) for y, z in yz_points] + [(back_x, y, z) for y, z in yz_points]
    faces: list[tuple[int, ...]] = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections["CHR_GUGU_DECALS"].objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("侧羽圆角", "BEVEL")
    bevel.width = 0.026
    bevel.segments = 3
    return obj


def create_side_groove(
    name: str,
    points: list[tuple[float, float, float]],
    material: bpy.types.Material,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = 0.011
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    bpy.data.collections["CHR_GUGU_DECALS"].objects.link(obj)
    curve.materials.append(material)
    return obj


def add_side_feathers() -> None:
    light = bpy.data.materials["MAT_GUGU_blue_feather_light"]
    mid = bpy.data.materials["MAT_GUGU_blue_feather_mid"]
    line = bpy.data.materials["MAT_GUGU_wing_line"]
    for name in list(bpy.data.objects.keys()):
        if name.startswith(("DEC_GUGU_WingSideLayer", "DEC_GUGU_WingSideGroove")):
            delete_object(name)

    upper = [
        (-0.96, 3.08),
        (-0.66, 3.00),
        (-0.36, 2.70),
        (-0.18, 2.24),
        (-0.20, 1.95),
        (-0.46, 2.16),
        (-0.76, 2.58),
    ]
    lower = [
        (-0.62, 2.70),
        (-0.30, 2.52),
        (0.14, 1.86),
        (0.18, 1.55),
        (-0.06, 1.72),
        (-0.38, 2.12),
    ]
    create_side_panel("DEC_GUGU_WingSideLayer.L.1", upper, 2.64, 2.58, light)
    create_side_panel("DEC_GUGU_WingSideLayer.L.2", lower, 2.67, 2.61, mid)
    create_side_panel("DEC_GUGU_WingSideLayer.R.1", upper, -2.64, -2.58, light)
    create_side_panel("DEC_GUGU_WingSideLayer.R.2", lower, -2.67, -2.61, mid)
    create_side_groove(
        "DEC_GUGU_WingSideGroove.L",
        [(2.695, -0.52, 2.67), (2.695, -0.20, 2.20), (2.695, 0.08, 1.72)],
        line,
    )
    create_side_groove(
        "DEC_GUGU_WingSideGroove.R",
        [(-2.695, -0.52, 2.67), (-2.695, -0.20, 2.20), (-2.695, 0.08, 1.72)],
        line,
    )


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage310-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage300 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    helpers = load_helpers()
    # 脸部仍停留在原位置；只恢复胸腹前侧的饱满度。
    helpers.set_world_depth(bpy.data.objects["CHR_GUGU_Torso"], -1.45, 1.20)
    helpers.set_world_depth(bpy.data.objects["DEC_GUGU_BellyPatch"], -1.58, -1.23)
    for side in ("R", "L"):
        helpers.set_world_depth(bpy.data.objects[f"CHR_GUGU_Wing.{side}"], -1.42, 0.34)
    add_side_feathers()
    bpy.context.scene["gugu_stage"] = "wing_depth_refined_310"
    bpy.context.scene["art_direction"] = "flat_face_full_body_layered_wings"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage310 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
