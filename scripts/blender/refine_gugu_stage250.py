"""以 stage230 为基线，生成柔和手绘式三渲二的 stage250。"""

from __future__ import annotations

import importlib.util
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-230-delivery-final.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-250-soft-npr.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
STAGE240_SCRIPT = ROOT / "scripts/blender/refine_gugu_stage240.py"


SOFT_PALETTES = {
    "MAT_GUGU_blue": "35B8F2",
    "MAT_GUGU_blue_shadow": "258FC7",
    "MAT_GUGU_cream": "FFF0C6",
    "MAT_GUGU_orange": "FF8448",
    "MAT_GUGU_red": "F05A4D",
    "MAT_GUGU_red_shadow": "C93635",
    "MAT_GUGU_gold": "F5B51D",
    "MAT_GUGU_gold_shadow": "CF8308",
}

FLAT_PALETTES = {
    "MAT_GUGU_navy": "082A4D",
    "MAT_GUGU_eye_navy": "061F3A",
    "MAT_GUGU_eye_blue": "147CB8",
    "MAT_GUGU_eye_white": "FFFDF7",
    "MAT_GUGU_white": "FFFDF7",
}


def load_stage240_helpers():
    spec = importlib.util.spec_from_file_location("gugu_stage240_helpers", STAGE240_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 stage240 精修脚本：{STAGE240_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def set_input(shader: bpy.types.Node, name: str, value) -> None:
    socket = shader.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def configure_soft_material(material: bpy.types.Material, color: str, helpers) -> None:
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (360, 0)
    shader = tree.nodes.new("ShaderNodeBsdfPrincipled")
    shader.location = (20, 0)
    base = helpers.hex_color(color)
    set_input(shader, "Base Color", base)
    set_input(shader, "Roughness", 0.78)
    set_input(shader, "Metallic", 0.0)
    set_input(shader, "IOR", 1.42)
    set_input(shader, "Specular IOR Level", 0.18)
    set_input(shader, "Coat Weight", 0.0)
    set_input(shader, "Subsurface Weight", 0.015)
    set_input(shader, "Emission Color", base)
    set_input(shader, "Emission Strength", 0.055)
    tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    material.diffuse_color = base


def configure_flat_material(material: bpy.types.Material, color: str, helpers) -> None:
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (340, 0)
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.location = (40, 0)
    emission.inputs["Color"].default_value = helpers.hex_color(color)
    emission.inputs["Strength"].default_value = 0.92
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    material.diffuse_color = helpers.hex_color(color)


def make_soft_material(name: str, color: str, helpers) -> bpy.types.Material:
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    configure_soft_material(material, color, helpers)
    return material


def replace_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def configure_materials(helpers) -> None:
    for name, color in SOFT_PALETTES.items():
        material = bpy.data.materials.get(name)
        if material:
            configure_soft_material(material, color, helpers)
    for name, color in FLAT_PALETTES.items():
        material = bpy.data.materials.get(name)
        if material:
            configure_flat_material(material, color, helpers)

    blue_layer = make_soft_material("MAT_GUGU_blue_layer", "2FA9E2", helpers)
    for name in (
        "DEC_GUGU_WingLayer.R.1",
        "DEC_GUGU_WingLayer.R.2",
        "DEC_GUGU_WingLayer.L.1",
        "DEC_GUGU_WingLayer.L.2",
    ):
        replace_material(bpy.data.objects[name], blue_layer)

    beak_lower = make_soft_material("MAT_GUGU_orange_lower", "EF6938", helpers)
    replace_material(bpy.data.objects["CHR_GUGU_Beak_Lower"], beak_lower)

    bag_body = make_soft_material("MAT_GUGU_gold_body", "E7A015", helpers)
    bag_flap = make_soft_material("MAT_GUGU_gold_flap", "FBC23C", helpers)
    bag_highlight = make_soft_material("MAT_GUGU_gold_highlight", "FFD15A", helpers)
    replace_material(bpy.data.objects["ACC_GUGU_Satchel_Body"], bag_body)
    replace_material(bpy.data.objects["ACC_GUGU_Satchel_Flap"], bag_flap)
    replace_material(bpy.data.objects["ACC_GUGU_Satchel_Ring"], bag_highlight)
    replace_material(bpy.data.objects["ACC_GUGU_Satchel_Button"], bag_highlight)


def taper_torso(helpers) -> None:
    torso = bpy.data.objects["CHR_GUGU_Torso"]
    center_x = 0.061
    z_min = 0.72
    z_max = 3.62

    def reshape(point: Vector) -> Vector:
        normalized = min(1.0, max(0.0, (point.z - z_min) / (z_max - z_min)))
        # 中下段保持饱满，肩颈处明显收窄，形成友好的梨形轮廓。
        if normalized >= 0.52:
            factor = 1.0 - 0.17 * ((normalized - 0.52) / 0.48) ** 1.35
        else:
            factor = 0.92 + 0.08 * (normalized / 0.52)
        point.x = center_x + (point.x - center_x) * factor
        return point

    helpers.mutate_world_vertices(torso, reshape)


def move_world_y(obj: bpy.types.Object, offset: float, helpers) -> None:
    def move(point: Vector) -> Vector:
        point.y += offset
        return point

    helpers.mutate_world_vertices(obj, move)


def create_shallow_decal(
    name: str,
    points: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    material: bpy.types.Material,
) -> bpy.types.Object:
    vertices = [(x, front_y, z) for x, z in points] + [(x, back_y, z) for x, z in points]
    count = len(points)
    faces = [tuple(range(count)), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection = bpy.data.collections.get("CHR_GUGU_DECALS") or bpy.context.scene.collection
    collection.objects.link(obj)
    mesh.materials.append(material)
    bevel = obj.modifiers.new("胸羽柔化", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 2
    return obj


def add_chest_tufts() -> None:
    material = bpy.data.materials["MAT_GUGU_blue"]
    tuft_specs = {
        "DEC_GUGU_ChestTuft.R.1": [(-1.03, 3.28), (-0.84, 3.19), (-0.95, 3.00)],
        "DEC_GUGU_ChestTuft.R.2": [(-0.96, 3.10), (-0.76, 3.01), (-0.86, 2.86)],
        "DEC_GUGU_ChestTuft.L.1": [(1.24, 3.27), (1.03, 3.18), (1.16, 2.99)],
        "DEC_GUGU_ChestTuft.L.2": [(1.16, 3.09), (0.98, 3.00), (1.08, 2.85)],
    }
    for name, points in tuft_specs.items():
        create_shallow_decal(name, points, -1.405, -1.385, material)


def refine_geometry(helpers) -> None:
    helpers.refine_geometry()
    taper_torso(helpers)

    # 第一轮围巾略薄，恢复布料宽度，同时把结与飘带拉回围巾后缘。
    helpers.scale_world_axis(bpy.data.objects["ACC_GUGU_Scarf_Wrap"], "Z", 1.10, 3.36)
    for name in ("ACC_GUGU_Scarf_Knot", "ACC_GUGU_Scarf_Tail_A", "ACC_GUGU_Scarf_Tail_B"):
        move_world_y(bpy.data.objects[name], -0.28, helpers)

    add_chest_tufts()


def configure_rendering(helpers) -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 540
    scene.render.resolution_y = 887
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    try:
        scene.view_settings.look = "Medium High Contrast"
    except TypeError:
        pass
    scene.view_settings.exposure = -0.10
    scene.view_settings.gamma = 1.0

    world = scene.world
    if world and world.use_nodes:
        lighting = world.node_tree.nodes.get("环境照明")
        camera_background = world.node_tree.nodes.get("相机暖白背景")
        if lighting:
            lighting.inputs["Color"].default_value = helpers.hex_color("D7E8F2")
            lighting.inputs["Strength"].default_value = 0.62
        if camera_background:
            camera_background.inputs["Color"].default_value = helpers.hex_color("FFF9F0")
            camera_background.inputs["Strength"].default_value = 0.8

    light_settings = {
        "主光": (560.0, 7.0, "FFE5CF"),
        "补光": (290.0, 6.0, "C3E5FF"),
        "轮廓光": (230.0, 5.5, "A2D9FF"),
    }
    for name, (energy, size, color) in light_settings.items():
        light = bpy.data.objects.get(name)
        if light and light.type == "LIGHT":
            light.data.energy = energy
            light.data.size = size
            light.data.color = helpers.hex_color(color)[:3]

    ground = bpy.data.materials.get("MAT_GUGU_ground")
    if ground:
        ground.use_nodes = True
        shader = ground.node_tree.nodes.get("Principled BSDF")
        if shader:
            base = helpers.hex_color("F7F1E7")
            set_input(shader, "Base Color", base)
            set_input(shader, "Roughness", 0.88)
            set_input(shader, "Emission Color", base)
            set_input(shader, "Emission Strength", 0.22)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage250-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage230 基线：{BASELINE_BLEND}")
    if Path(bpy.data.filepath) != BASELINE_BLEND:
        bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))

    helpers = load_stage240_helpers()
    refine_geometry(helpers)
    configure_materials(helpers)
    configure_rendering(helpers)
    bpy.context.scene["gugu_stage"] = "soft_npr_250"
    bpy.context.scene["art_direction"] = "animation_soft_npr"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage250 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
