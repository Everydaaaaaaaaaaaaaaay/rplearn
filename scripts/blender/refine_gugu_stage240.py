"""在 stage230 基线上进行动画化形体与三渲二美术精修。"""

from __future__ import annotations

import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-230-delivery-final.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-240-art-refined.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


TOON_PALETTES = {
    "MAT_GUGU_blue": ("208CC7", "35B8F2", "72D2F8"),
    "MAT_GUGU_blue_shadow": ("176A9B", "258FC7", "48B4E8"),
    "MAT_GUGU_cream": ("DFC99B", "FFF0C6", "FFF8E2"),
    "MAT_GUGU_orange": ("D6542B", "FF8448", "FFAD68"),
    "MAT_GUGU_red": ("BC352E", "F05A4D", "FF826C"),
    "MAT_GUGU_red_shadow": ("8F2728", "C93635", "EF574D"),
    "MAT_GUGU_gold": ("B66C00", "F5B51D", "FFD65A"),
    "MAT_GUGU_gold_shadow": ("8E5200", "CF8308", "F0A91D"),
}

FLAT_PALETTES = {
    "MAT_GUGU_navy": "082A4D",
    "MAT_GUGU_eye_navy": "061F3A",
    "MAT_GUGU_eye_blue": "147CB8",
    "MAT_GUGU_eye_white": "FFFDF7",
    "MAT_GUGU_white": "FFFDF7",
}


def hex_color(value: str) -> tuple[float, float, float, float]:
    """将 sRGB 十六进制色转换为 Blender 线性色。"""
    value = value.lstrip("#")
    srgb = [int(value[index : index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        for channel in srgb
    ]
    return tuple(linear) + (1.0,)


def object_world_vertices(obj: bpy.types.Object) -> list[Vector]:
    return [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]


def mutate_world_vertices(obj: bpy.types.Object, mutator) -> None:
    inverse = obj.matrix_world.inverted()
    for vertex in obj.data.vertices:
        world = obj.matrix_world @ vertex.co
        vertex.co = inverse @ mutator(world)
    obj.data.update()


def set_world_depth(obj: bpy.types.Object, front: float, back: float) -> None:
    """在世界 Y 轴上重映射厚度，负 Y 为正面。"""
    vertices = object_world_vertices(obj)
    source_front = min(point.y for point in vertices)
    source_back = max(point.y for point in vertices)
    extent = max(1e-6, source_back - source_front)

    def remap(point: Vector) -> Vector:
        ratio = (point.y - source_front) / extent
        point.y = front + ratio * (back - front)
        return point

    mutate_world_vertices(obj, remap)


def scale_world_axis(obj: bpy.types.Object, axis: str, factor: float, anchor: float) -> None:
    index = {"X": 0, "Y": 1, "Z": 2}[axis]

    def scale(point: Vector) -> Vector:
        point[index] = anchor + (point[index] - anchor) * factor
        return point

    mutate_world_vertices(obj, scale)


def shape_head_depth(obj: bpy.types.Object) -> None:
    """压平前后深度并在顶部、下颌处收圆，避免几何球和方盒侧影。"""
    points = object_world_vertices(obj)
    z_min = min(point.z for point in points)
    z_max = max(point.z for point in points)
    center = (z_min + z_max) * 0.5
    half = (z_max - z_min) * 0.5

    def reshape(point: Vector) -> Vector:
        vertical = min(1.0, abs((point.z - center) / max(half, 1e-6)))
        round_factor = 0.84 * (1.0 - 0.13 * vertical**2)
        point.y *= round_factor
        return point

    mutate_world_vertices(obj, reshape)


def shape_torso_depth(obj: bpy.types.Object) -> None:
    points = object_world_vertices(obj)
    z_min = min(point.z for point in points)
    z_max = max(point.z for point in points)
    center = (z_min + z_max) * 0.5
    half = (z_max - z_min) * 0.5

    def reshape(point: Vector) -> Vector:
        vertical = min(1.0, abs((point.z - center) / max(half, 1e-6)))
        point.y *= 0.80 * (1.0 - 0.08 * vertical**2)
        return point

    mutate_world_vertices(obj, reshape)


def clear_material_nodes(material: bpy.types.Material) -> tuple[bpy.types.NodeTree, bpy.types.Node]:
    material.use_nodes = True
    tree = material.node_tree
    tree.nodes.clear()
    output = tree.nodes.new("ShaderNodeOutputMaterial")
    output.location = (520, 0)
    return tree, output


def configure_flat_material(material: bpy.types.Material, color: str) -> None:
    tree, output = clear_material_nodes(material)
    emission = tree.nodes.new("ShaderNodeEmission")
    emission.location = (250, 0)
    emission.inputs["Color"].default_value = hex_color(color)
    emission.inputs["Strength"].default_value = 1.0
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    material.diffuse_color = hex_color(color)


def configure_toon_material(
    material: bpy.types.Material,
    shadow: str,
    base: str,
    highlight: str,
) -> None:
    tree, output = clear_material_nodes(material)
    diffuse = tree.nodes.new("ShaderNodeBsdfDiffuse")
    diffuse.location = (-520, 0)
    diffuse.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    diffuse.inputs["Roughness"].default_value = 0.0

    shader_to_rgb = tree.nodes.new("ShaderNodeShaderToRGB")
    shader_to_rgb.location = (-300, 0)
    ramp = tree.nodes.new("ShaderNodeValToRGB")
    ramp.location = (-70, 0)
    ramp.color_ramp.interpolation = "CONSTANT"
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = hex_color(shadow)
    ramp.color_ramp.elements[1].position = 0.43
    ramp.color_ramp.elements[1].color = hex_color(base)
    light_element = ramp.color_ramp.elements.new(0.78)
    light_element.color = hex_color(highlight)

    emission = tree.nodes.new("ShaderNodeEmission")
    emission.location = (270, 0)
    emission.inputs["Strength"].default_value = 1.0
    tree.links.new(diffuse.outputs["BSDF"], shader_to_rgb.inputs["Shader"])
    tree.links.new(shader_to_rgb.outputs["Color"], ramp.inputs["Fac"])
    tree.links.new(ramp.outputs["Color"], emission.inputs["Color"])
    tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    material.diffuse_color = hex_color(base)


def ensure_blue_layer_material() -> bpy.types.Material:
    name = "MAT_GUGU_blue_layer"
    material = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    configure_toon_material(material, "1A79AF", "2FA8E0", "5FC7F0")
    return material


def replace_object_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.material_index = 0


def configure_materials() -> None:
    for name, colors in TOON_PALETTES.items():
        material = bpy.data.materials.get(name)
        if material:
            configure_toon_material(material, *colors)
    for name, color in FLAT_PALETTES.items():
        material = bpy.data.materials.get(name)
        if material:
            configure_flat_material(material, color)

    layer_material = ensure_blue_layer_material()
    for name in (
        "DEC_GUGU_WingLayer.R.1",
        "DEC_GUGU_WingLayer.R.2",
        "DEC_GUGU_WingLayer.L.1",
        "DEC_GUGU_WingLayer.L.2",
    ):
        obj = bpy.data.objects.get(name)
        if obj:
            replace_object_material(obj, layer_material)


def refine_geometry() -> None:
    head = bpy.data.objects["CHR_GUGU_Head"]
    torso = bpy.data.objects["CHR_GUGU_Torso"]
    shape_head_depth(head)
    shape_torso_depth(torso)

    # 面部保持 2.5D 浅浮雕，不让眼眶、脸颊产生玩具零件感。
    for name in ("CHR_GUGU_Eye.R", "CHR_GUGU_Eye.L"):
        obj = bpy.data.objects[name]
        set_world_depth(obj, -1.58, -1.43)
        scale_world_axis(obj, "X", 0.96, obj.location.x)
        scale_world_axis(obj, "Z", 0.97, obj.location.z)
    for name in ("CHR_GUGU_Brow.R", "CHR_GUGU_Brow.L"):
        set_world_depth(bpy.data.objects[name], -1.48, -1.43)
    for name in ("CHR_GUGU_CheekPad.R", "CHR_GUGU_CheekPad.L"):
        obj = bpy.data.objects[name]
        set_world_depth(obj, -1.40, -1.22)
        points = object_world_vertices(obj)
        z_center = (min(point.z for point in points) + max(point.z for point in points)) * 0.5
        scale_world_axis(obj, "Z", 0.88, z_center)

    set_world_depth(bpy.data.objects["CHR_GUGU_Beak_Upper"], -2.00, -1.43)
    set_world_depth(bpy.data.objects["CHR_GUGU_Beak_Lower"], -1.82, -1.42)
    lower = bpy.data.objects["CHR_GUGU_Beak_Lower"]
    lower_points = object_world_vertices(lower)
    lower_center_z = (min(point.z for point in lower_points) + max(point.z for point in lower_points)) * 0.5
    scale_world_axis(lower, "Z", 0.82, lower_center_z)
    set_world_depth(bpy.data.objects["DEC_GUGU_BeakNostril.LR"], -2.025, -2.005)

    # 翅膀压成清晰的动画剪影，并用浅层羽片而非球面细节表达层次。
    for side in ("R", "L"):
        set_world_depth(bpy.data.objects[f"CHR_GUGU_Wing.{side}"], -1.30, -0.70)
        set_world_depth(bpy.data.objects[f"DEC_GUGU_WingLayer.{side}.1"], -1.37, -1.30)
        set_world_depth(bpy.data.objects[f"DEC_GUGU_WingLayer.{side}.2"], -1.39, -1.32)
        set_world_depth(bpy.data.objects[f"DEC_GUGU_WingFeatherDetail.{side}"], -1.415, -1.395)

    # 腹部花色与配饰贴合压平后的身体表面。
    set_world_depth(bpy.data.objects["DEC_GUGU_BellyPatch"], -1.39, -1.16)
    set_world_depth(bpy.data.objects["ACC_GUGU_Satchel_Strap"], -1.49, -1.42)

    scarf = bpy.data.objects["ACC_GUGU_Scarf_Wrap"]
    set_world_depth(scarf, -1.44, 0.76)
    scale_world_axis(scarf, "Z", 0.82, 3.36)

    # 脚趾更扁、更宽，轮廓接近手绘角色而非珠状球体。
    for name, center_x in (("CHR_GUGU_Foot.R", -0.69), ("CHR_GUGU_Foot.L", 0.87)):
        foot = bpy.data.objects[name]
        scale_world_axis(foot, "X", 1.08, center_x)
        scale_world_axis(foot, "Z", 0.72, 0.10)
        set_world_depth(foot, -0.70, 0.15)


def configure_rendering() -> None:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 540
    scene.render.resolution_y = 887
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False

    try:
        scene.view_settings.view_transform = "Standard"
        scene.view_settings.look = "Medium High Contrast"
        scene.view_settings.exposure = -0.15
        scene.view_settings.gamma = 1.0
    except TypeError:
        scene.view_settings.view_transform = "Standard"

    world = scene.world
    if world and world.use_nodes:
        lighting = world.node_tree.nodes.get("环境照明")
        camera_background = world.node_tree.nodes.get("相机暖白背景")
        if lighting:
            lighting.inputs["Color"].default_value = hex_color("A9C9DF")
            lighting.inputs["Strength"].default_value = 0.22
        if camera_background:
            camera_background.inputs["Color"].default_value = hex_color("FFF9EF")
            camera_background.inputs["Strength"].default_value = 1.0

    light_settings = {
        "主光": (700.0, "FFE3C7"),
        "补光": (210.0, "A8D9FF"),
        "轮廓光": (330.0, "8CCFFF"),
    }
    for name, (energy, color) in light_settings.items():
        light = bpy.data.objects.get(name)
        if light and light.type == "LIGHT":
            light.data.energy = energy
            light.data.color = hex_color(color)[:3]

    ground = bpy.data.materials.get("MAT_GUGU_ground")
    if ground:
        ground.use_nodes = True
        shader = ground.node_tree.nodes.get("Principled BSDF")
        if shader:
            ground_color = hex_color("F6F0E5")
            shader.inputs["Base Color"].default_value = ground_color
            shader.inputs["Roughness"].default_value = 0.82
            if "Emission Strength" in shader.inputs:
                shader.inputs["Emission Strength"].default_value = 0.0


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage240-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage230 基线：{BASELINE_BLEND}")
    if Path(bpy.data.filepath) != BASELINE_BLEND:
        bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))

    refine_geometry()
    configure_materials()
    configure_rendering()
    bpy.context.scene["gugu_stage"] = "art_refined_240"
    bpy.context.scene["art_direction"] = "animation_2_5d_toon"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage240 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
