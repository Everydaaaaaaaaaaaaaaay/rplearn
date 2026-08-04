"""重建关键轮廓件，生成 stage260 动画化造型精修版本。"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-250-soft-npr.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-260-shape-polished.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage240.py"
STAGE250_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage250.py"


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载精修脚本：{path}")
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


def create_extruded_contour(
    name: str,
    points: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    bevel_width: float = 0.025,
) -> bpy.types.Object:
    count = len(points)
    vertices = [(x, front_y, z) for x, z in points] + [(x, back_y, z) for x, z in points]
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(reversed(range(count))))
    faces.append(tuple(range(count, count * 2)))
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    bevel = obj.modifiers.new("轮廓柔化", "BEVEL")
    bevel.width = bevel_width
    bevel.segments = 3
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def create_flat_scarf_wrap(material: bpy.types.Material) -> bpy.types.Object:
    """用圆角矩形截面的椭圆布带替代三根管状围巾。"""
    segments = 96
    center_x = 0.21
    center_z = 3.35
    radius_x = 1.55
    radius_y = 1.22
    radial_half = 0.14
    vertical_half = 0.30
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    for index in range(segments):
        angle = math.tau * index / segments
        cosine = math.cos(angle)
        sine = math.sin(angle)
        center = Vector((center_x + radius_x * cosine, radius_y * sine, center_z))
        radial = Vector((cosine, sine, 0.0))
        vertices.extend(
            [
                tuple(center + radial * radial_half + Vector((0.0, 0.0, vertical_half))),
                tuple(center - radial * radial_half + Vector((0.0, 0.0, vertical_half))),
                tuple(center - radial * radial_half - Vector((0.0, 0.0, vertical_half))),
                tuple(center + radial * radial_half - Vector((0.0, 0.0, vertical_half))),
            ]
        )
    for index in range(segments):
        following = (index + 1) % segments
        current = index * 4
        nxt = following * 4
        faces.extend(
            [
                (current, nxt, nxt + 1, current + 1),
                (current + 1, nxt + 1, nxt + 2, current + 2),
                (current + 2, nxt + 2, nxt + 3, current + 3),
                (current + 3, nxt + 3, nxt, current),
            ]
        )
    mesh = bpy.data.meshes.new("ACC_GUGU_Scarf_Wrap_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("ACC_GUGU_Scarf_Wrap", mesh)
    bpy.data.collections["CHR_GUGU_ACCESSORIES"].objects.link(obj)
    mesh.materials.append(material)
    bevel = obj.modifiers.new("布带圆角", "BEVEL")
    bevel.width = 0.075
    bevel.segments = 4
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def scarf_front_y(x: float) -> float:
    normalized = max(-0.98, min(0.98, (x - 0.21) / 1.55))
    return -1.22 * math.sqrt(max(0.0, 1.0 - normalized * normalized)) - 0.151


def create_scarf_fold(
    name: str,
    z: float,
    height: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    samples = 25
    top: list[tuple[float, float, float]] = []
    bottom: list[tuple[float, float, float]] = []
    for index in range(samples):
        ratio = index / (samples - 1)
        x = -1.27 + ratio * 2.96
        sag = 0.018 * math.sin(ratio * math.pi)
        y = scarf_front_y(x)
        top.append((x, y, z + height * 0.5 - sag))
        bottom.append((x, y - 0.008, z - height * 0.5 - sag))
    vertices = top + list(reversed(bottom))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], [tuple(range(len(vertices)))])
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.data.collections["CHR_GUGU_DECALS"].objects.link(obj)
    mesh.materials.append(material)
    bevel = obj.modifiers.new("布褶柔化", "BEVEL")
    bevel.width = 0.012
    bevel.segments = 2
    return obj


def rebuild_scarf(helpers) -> None:
    delete_object("ACC_GUGU_Scarf_Wrap")
    delete_object("DEC_GUGU_ScarfFold_Dark")
    delete_object("DEC_GUGU_ScarfFold_Light")
    red = bpy.data.materials["MAT_GUGU_red"]
    red_shadow = bpy.data.materials["MAT_GUGU_red_shadow"]
    light = bpy.data.materials.get("MAT_GUGU_red_light")
    if light is None:
        stage250 = load_module("gugu_stage250_materials", STAGE250_SCRIPT)
        light = stage250.make_soft_material("MAT_GUGU_red_light", "FF7561", helpers)
    create_flat_scarf_wrap(red)
    create_scarf_fold("DEC_GUGU_ScarfFold_Dark", 3.22, 0.045, red_shadow)
    create_scarf_fold("DEC_GUGU_ScarfFold_Light", 3.48, 0.035, light)

    knot = bpy.data.objects["ACC_GUGU_Scarf_Knot"]
    helpers.set_world_depth(knot, 0.31, 0.62)
    helpers.scale_world_axis(knot, "Z", 0.84, 3.38)
    # stage250 的飘带仍与结相距约 0.75，直接回拉至同一深度区间。
    for name in ("ACC_GUGU_Scarf_Tail_A", "ACC_GUGU_Scarf_Tail_B"):
        obj = bpy.data.objects[name]

        def move(point: Vector) -> Vector:
            point.y -= 0.75
            return point

        helpers.mutate_world_vertices(obj, move)


def rebuild_feet() -> None:
    orange = bpy.data.materials["MAT_GUGU_orange"]
    collection = bpy.data.collections["CHR_GUGU_GEO"]
    outline = [
        (-0.48, 0.08),
        (-0.50, 0.15),
        (-0.43, 0.22),
        (-0.30, 0.23),
        (-0.22, 0.29),
        (-0.07, 0.28),
        (0.02, 0.22),
        (0.13, 0.25),
        (0.28, 0.23),
        (0.40, 0.17),
        (0.42, 0.10),
        (0.34, 0.055),
        (0.14, 0.04),
        (-0.07, 0.055),
        (-0.30, 0.04),
    ]
    for name, center_x in (("CHR_GUGU_Foot.R", -0.69), ("CHR_GUGU_Foot.L", 0.87)):
        delete_object(name)
        points = [(center_x + x, z) for x, z in outline]
        create_extruded_contour(name, points, -0.68, 0.14, orange, collection, bevel_width=0.035)


def refine_wings(stage250) -> None:
    helpers = load_module("gugu_stage240_helpers_for_wings", STAGE240_SCRIPT)
    light = stage250.make_soft_material("MAT_GUGU_blue_feather_light", "62C9F2", helpers)
    mid = stage250.make_soft_material("MAT_GUGU_blue_feather_mid", "2B9ED7", helpers)
    for side in ("R", "L"):
        replace_material(bpy.data.objects[f"DEC_GUGU_WingLayer.{side}.1"], light)
        replace_material(bpy.data.objects[f"DEC_GUGU_WingLayer.{side}.2"], mid)


def refine_bag_and_beak(helpers) -> None:
    for name in ("ACC_GUGU_Satchel_Body", "ACC_GUGU_Satchel_Flap"):
        obj = bpy.data.objects[name]
        helpers.scale_world_axis(obj, "X", 1.10, 1.30)
        helpers.scale_world_axis(obj, "Z", 0.90, 1.50)
    helpers.set_world_depth(bpy.data.objects["ACC_GUGU_Satchel_Body"], -1.60, -1.30)
    helpers.set_world_depth(bpy.data.objects["ACC_GUGU_Satchel_Flap"], -1.66, -1.52)
    helpers.set_world_depth(bpy.data.objects["ACC_GUGU_Satchel_Button"], -1.72, -1.67)

    for name in ("CHR_GUGU_Beak_Upper", "CHR_GUGU_Beak_Lower"):
        obj = bpy.data.objects[name]
        for modifier in obj.modifiers:
            if modifier.type == "BEVEL":
                modifier.width = 0.075
                modifier.segments = 4
        for polygon in obj.data.polygons:
            polygon.use_smooth = True


def lean_primary_crest(helpers) -> None:
    crest = bpy.data.objects["CHR_GUGU_Crest_A"]
    points = helpers.object_world_vertices(crest)
    z_min = min(point.z for point in points)
    z_max = max(point.z for point in points)

    def lean(point: Vector) -> Vector:
        ratio = (point.z - z_min) / max(1e-6, z_max - z_min)
        point.x -= 0.16 * ratio**1.3
        return point

    helpers.mutate_world_vertices(crest, lean)


def create_shadow_material(name: str, alpha: float, helpers) -> bpy.types.Material:
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    transparent = tree.nodes.new("ShaderNodeBsdfTransparent")
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = helpers.hex_color("AAB9BC")
    mix = tree.nodes.new("ShaderNodeMixShader")
    mix.inputs[0].default_value = alpha
    tree.links.new(transparent.outputs["BSDF"], mix.inputs[1])
    tree.links.new(emission.outputs["Emission"], mix.inputs[2])
    tree.links.new(mix.outputs["Shader"], output.inputs["Surface"])
    if hasattr(material, "surface_render_method"):
        material.surface_render_method = "DITHERED"
    elif hasattr(material, "blend_method"):
        material.blend_method = "BLEND"
    return material


def replace_ground_with_soft_shadow(helpers) -> None:
    ground = bpy.data.objects.get("STAGE_地面")
    if ground:
        ground.hide_render = True
    for name in ("STAGE_软投影_A", "STAGE_软投影_B", "STAGE_软投影_C"):
        delete_object(name)
    stage = bpy.data.collections["CHR_GUGU_STAGE"]
    specs = [
        ("STAGE_软投影_A", 1.70, 0.58, 0.035),
        ("STAGE_软投影_B", 1.38, 0.45, 0.045),
        ("STAGE_软投影_C", 1.05, 0.34, 0.055),
    ]
    for index, (name, radius_x, radius_y, alpha) in enumerate(specs):
        material = create_shadow_material(f"MAT_GUGU_shadow_{index}", alpha, helpers)
        vertices = [(0.0, 0.0, -0.035 + index * 0.001)]
        segments = 96
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append((radius_x * math.cos(angle), radius_y * math.sin(angle) - 0.18, -0.035 + index * 0.001))
        faces = []
        for segment in range(segments):
            following = (segment + 1) % segments
            faces.append((0, 1 + segment, 1 + following))
        mesh = bpy.data.meshes.new(f"{name}_Mesh")
        mesh.from_pydata(vertices, [], faces)
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        stage.objects.link(obj)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage260-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage250 基线：{BASELINE_BLEND}")
    if Path(bpy.data.filepath) != BASELINE_BLEND:
        bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))

    helpers = load_module("gugu_stage240_helpers", STAGE240_SCRIPT)
    stage250 = load_module("gugu_stage250_helpers", STAGE250_SCRIPT)
    for name in list(bpy.data.objects.keys()):
        if name.startswith("DEC_GUGU_ChestTuft."):
            delete_object(name)
    rebuild_scarf(helpers)
    rebuild_feet()
    refine_wings(stage250)
    refine_bag_and_beak(helpers)
    lean_primary_crest(helpers)
    replace_ground_with_soft_shadow(helpers)
    bpy.context.scene["gugu_stage"] = "shape_polished_260"
    bpy.context.scene["art_direction"] = "animation_soft_npr_contour_rebuilt"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage260 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
