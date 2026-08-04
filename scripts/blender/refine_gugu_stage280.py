"""精修嘴喙、邮差包、羽沟和脚趾可读性，生成 stage280。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-270-silhouette-refined.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-280-character-detail.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage240.py"
STAGE250_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage250.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载脚本：{path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def delete_object(name: str) -> None:
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)


def replace_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def create_contour_loft(
    name: str,
    contour: list[tuple[float, float]],
    center: tuple[float, float],
    rings: list[tuple[float, float]],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    """沿 Y 轴以不同轮廓缩放放样，获得圆润但不球化的 2.5D 体积。"""
    center_x, center_z = center
    count = len(contour)
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for y, scale in rings:
        for x, z in contour:
            vertices.append((center_x + (x - center_x) * scale, y, center_z + (z - center_z) * scale))
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
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("软体圆角", "BEVEL")
    bevel.width = 0.045
    bevel.segments = 3
    return obj


def rebuild_beak() -> None:
    orange = bpy.data.materials["MAT_GUGU_orange"]
    orange_lower = bpy.data.materials["MAT_GUGU_orange_lower"]
    face = bpy.data.collections["CHR_GUGU_FACE"]
    upper_contour = [
        (-0.29, 4.25),
        (-0.17, 4.49),
        (0.18, 4.62),
        (0.53, 4.50),
        (0.67, 4.25),
        (0.19, 4.07),
    ]
    lower_contour = [
        (-0.22, 4.13),
        (0.18, 4.01),
        (0.59, 4.13),
        (0.52, 3.90),
        (0.18, 3.73),
        (-0.15, 3.90),
    ]
    delete_object("CHR_GUGU_Beak_Upper")
    delete_object("CHR_GUGU_Beak_Lower")
    create_contour_loft(
        "CHR_GUGU_Beak_Upper",
        upper_contour,
        (0.19, 4.31),
        [(-2.00, 0.58), (-1.80, 0.92), (-1.58, 1.00), (-1.43, 0.82)],
        orange,
        face,
    )
    create_contour_loft(
        "CHR_GUGU_Beak_Lower",
        lower_contour,
        (0.18, 3.99),
        [(-1.84, 0.62), (-1.68, 0.95), (-1.53, 1.00), (-1.42, 0.80)],
        orange_lower,
        face,
    )


def create_extruded_contour(
    name: str,
    points: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    bevel_width: float,
) -> bpy.types.Object:
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
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("配饰圆角", "BEVEL")
    bevel.width = bevel_width
    bevel.segments = 4
    return obj


def create_curve_detail(
    name: str,
    points: list[tuple[float, float, float]],
    radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 3
    curve.bevel_depth = radius
    curve.bevel_resolution = 3
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    curve.materials.append(material)
    return obj


def rebuild_satchel() -> None:
    accessories = bpy.data.collections["CHR_GUGU_ACCESSORIES"]
    decals = bpy.data.collections["CHR_GUGU_DECALS"]
    body_material = bpy.data.materials["MAT_GUGU_gold_body"]
    flap_material = bpy.data.materials["MAT_GUGU_gold_flap"]
    highlight_material = bpy.data.materials["MAT_GUGU_gold_highlight"]
    seam_material = bpy.data.materials["MAT_GUGU_gold_shadow"]
    body = [
        (0.70, 1.96),
        (0.78, 2.08),
        (1.74, 2.08),
        (1.88, 1.95),
        (1.91, 1.02),
        (1.78, 0.84),
        (0.88, 0.84),
        (0.70, 1.02),
    ]
    flap = [
        (0.68, 2.06),
        (0.78, 2.22),
        (1.77, 2.22),
        (1.92, 2.03),
        (1.83, 1.70),
        (1.31, 1.57),
        (0.78, 1.70),
    ]
    for name in (
        "ACC_GUGU_Satchel_Body",
        "ACC_GUGU_Satchel_Flap",
        "ACC_GUGU_Satchel_Button",
        "DEC_GUGU_Satchel_Seam",
    ):
        delete_object(name)
    create_extruded_contour("ACC_GUGU_Satchel_Body", body, -1.61, -1.31, body_material, accessories, 0.085)
    create_extruded_contour("ACC_GUGU_Satchel_Flap", flap, -1.70, -1.57, flap_material, accessories, 0.065)

    button_points = []
    for index in range(32):
        angle = __import__("math").tau * index / 32
        button_points.append((1.62 + 0.105 * __import__("math").cos(angle), 1.83 + 0.105 * __import__("math").sin(angle)))
    create_extruded_contour(
        "ACC_GUGU_Satchel_Button",
        button_points,
        -1.755,
        -1.70,
        highlight_material,
        decals,
        0.012,
    )

    create_curve_detail(
        "DEC_GUGU_Satchel_Seam",
        [
            (0.83, -1.705, 1.52),
            (0.83, -1.705, 1.06),
            (1.00, -1.705, 0.94),
            (1.68, -1.705, 0.94),
            (1.80, -1.705, 1.08),
            (1.80, -1.705, 1.46),
        ],
        0.016,
        seam_material,
        decals,
    )


def refine_muzzle(helpers) -> None:
    for name in ("CHR_GUGU_CheekPad.R", "CHR_GUGU_CheekPad.L"):
        helpers.set_world_depth(bpy.data.objects[name], -1.50, -1.22)


def add_line_details(helpers, stage250) -> None:
    decals = bpy.data.collections["CHR_GUGU_DECALS"]
    wing_line = bpy.data.materials.get("MAT_GUGU_wing_line") or bpy.data.materials.new("MAT_GUGU_wing_line")
    helpers.configure_flat_material(wing_line, "167EAF")
    for name in ("DEC_GUGU_WingFeatherDetail.R", "DEC_GUGU_WingFeatherDetail.L"):
        replace_material(bpy.data.objects[name], wing_line)

    toe_line = bpy.data.materials.get("MAT_GUGU_toe_line")
    if toe_line is None:
        toe_line = stage250.make_soft_material("MAT_GUGU_toe_line", "D65B31", helpers)
    for name in list(bpy.data.objects.keys()):
        if name.startswith("DEC_GUGU_ToeGroove"):
            delete_object(name)
    for side, center_x in (("R", -0.69), ("L", 0.87)):
        create_curve_detail(
            f"DEC_GUGU_ToeGroove.{side}.1",
            [(center_x - 0.12, -0.685, 0.23), (center_x - 0.08, -0.69, 0.13)],
            0.010,
            toe_line,
            decals,
        )
        create_curve_detail(
            f"DEC_GUGU_ToeGroove.{side}.2",
            [(center_x + 0.18, -0.685, 0.23), (center_x + 0.12, -0.69, 0.13)],
            0.010,
            toe_line,
            decals,
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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage280-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage270 基线：{BASELINE_BLEND}")
    # 每次强制重载已验收的上一阶段，避免失败重跑继承半成品场景。
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    helpers = load_module("gugu_stage240_helpers", STAGE240_SCRIPT)
    stage250 = load_module("gugu_stage250_helpers", STAGE250_SCRIPT)
    if bpy.data.materials.get("MAT_GUGU_gold_shadow") is None:
        stage250.make_soft_material("MAT_GUGU_gold_shadow", "CF8308", helpers)
    rebuild_beak()
    rebuild_satchel()
    refine_muzzle(helpers)
    add_line_details(helpers, stage250)
    bpy.context.scene["gugu_stage"] = "character_detail_280"
    bpy.context.scene["art_direction"] = "animation_soft_npr_character_detail"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage280 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
