"""生成咕咕 3D/2.5D 吉祥物的第一版可绑定基础模型。"""

from __future__ import annotations

import math
import os
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "Assets/Brand/Model/source"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders"
BLEND_PATH = MODEL_DIR / "gugu-model-v1.blend"
RENDER_PATH = RENDER_DIR / "gugu-model-v1-front.png"
TRANSPARENT_RENDER_PATH = RENDER_DIR / "gugu-model-v1-front-transparent.png"


PALETTE = {
    "blue": "42B9F5",
    "blue_light": "78D7FF",
    "blue_shadow": "198ACD",
    "cream": "FFF0C5",
    "cream_shadow": "F4CF8A",
    "navy": "082A4D",
    "iris": "105A91",
    "white": "FFFDF7",
    "orange": "FF7041",
    "orange_light": "FF9568",
    "mouth": "791F2B",
    "tongue": "FF665D",
    "scarf": "F04F43",
    "scarf_shadow": "C93435",
    "gold": "F7B51E",
    "gold_shadow": "D48608",
    "ground": "F7F4EF",
}


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    value = hex_value.lstrip("#")
    return tuple(int(value[index:index + 2], 16) / 255 for index in (0, 2, 4)) + (1.0,)


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for datablocks in (bpy.data.curves, bpy.data.meshes, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for datablock in list(datablocks):
            if datablock.users == 0:
                datablocks.remove(datablock)


def make_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def move_to_collection(obj: bpy.types.Object, collection: bpy.types.Collection) -> None:
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)


def make_material(
    name: str,
    color: str,
    *,
    roughness: float = 0.58,
    metallic: float = 0.0,
    subsurface: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = srgb(color)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = srgb(color)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Metallic"].default_value = metallic
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = 0.08
        shader.inputs["Coat Roughness"].default_value = 0.42
    if "Subsurface Weight" in shader.inputs:
        shader.inputs["Subsurface Weight"].default_value = subsurface
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    obj.data.materials.append(material)


def smooth(obj: bpy.types.Object) -> None:
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def add_uv_sphere(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    segments: int = 64,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=max(24, segments // 2),
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    assign_material(obj, material)
    smooth(obj)
    move_to_collection(obj, collection)
    return obj


def add_curve(
    name: str,
    points: list[tuple[float, float, float]],
    bevel: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    cyclic: bool = False,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(name, type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 24
    curve.bevel_depth = bevel
    curve.bevel_resolution = 7
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for bezier_point, coordinate in zip(spline.bezier_points, points):
        bezier_point.co = coordinate
        bezier_point.handle_left_type = "AUTO"
        bezier_point.handle_right_type = "AUTO"
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    assign_material(obj, material)
    return obj


def add_extruded_shape(
    name: str,
    contour: list[tuple[float, float]],
    y_front: float,
    thickness: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    bevel: float = 0.06,
) -> bpy.types.Object:
    front = [(x, y_front, z) for x, z in contour]
    back_y = y_front + thickness
    back = [(x, back_y, z) for x, z in contour]
    vertices = front + back
    count = len(contour)
    faces: list[tuple[int, ...]] = []
    faces.append(tuple(range(count)))
    faces.append(tuple(range(count, count * 2))[::-1])
    for index in range(count):
        next_index = (index + 1) % count
        faces.append((index, next_index, count + next_index, count + index))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    assign_material(obj, material)
    bevel_modifier = obj.modifiers.new("柔和倒角", "BEVEL")
    bevel_modifier.width = bevel
    bevel_modifier.segments = 5
    smooth(obj)
    return obj


def add_rounded_cube(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.18,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    modifier = obj.modifiers.new("柔和倒角", "BEVEL")
    modifier.width = bevel
    modifier.segments = 8
    smooth(obj)
    move_to_collection(obj, collection)
    return obj


def add_feather_group(
    prefix: str,
    side: int,
    materials: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
) -> None:
    angle = side * math.radians(25)
    add_uv_sphere(
        f"{prefix}_翼掌",
        (side * 1.90, -0.42, 3.34),
        (0.60, 0.46, 1.15),
        materials["blue"],
        collection,
        rotation=(0, angle, 0),
    )
    feather_data = [
        (2.23, 2.67, 0.20, 0.27, 0.48, 34),
        (2.08, 2.54, 0.18, 0.25, 0.42, 19),
        (1.93, 2.48, 0.16, 0.23, 0.36, 5),
    ]
    for index, (x, z, sx, sy, sz, degrees) in enumerate(feather_data, start=1):
        add_uv_sphere(
            f"{prefix}_飞羽_{index}",
            (side * x, -0.63 - index * 0.015, z),
            (sx, sy, sz),
            materials["blue"],
            collection,
            rotation=(0, side * math.radians(degrees), 0),
            segments=48,
        )
    add_curve(
        f"{prefix}_羽纹",
        [(side * 1.69, -1.00, 3.64), (side * 1.95, -1.03, 3.37), (side * 2.13, -1.01, 3.08)],
        0.030,
        materials["blue_shadow"],
        collection,
    )


def add_eye(
    prefix: str,
    x: float,
    materials: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
) -> None:
    add_uv_sphere(f"{prefix}_眼眶", (x, -1.33, 5.45), (0.50, 0.15, 0.70), materials["navy"], collection)
    add_uv_sphere(f"{prefix}_眼白", (x, -1.49, 5.45), (0.45, 0.075, 0.64), materials["cream"], collection)
    add_uv_sphere(f"{prefix}_瞳孔", (x, -1.59, 5.44), (0.34, 0.048, 0.49), materials["navy"], collection)
    add_uv_sphere(f"{prefix}_虹膜柔光", (x + 0.085, -1.65, 5.23), (0.066, 0.016, 0.082), materials["iris"], collection, segments=36)
    add_uv_sphere(f"{prefix}_主高光", (x - 0.12, -1.68, 5.66), (0.11, 0.013, 0.14), materials["white"], collection, segments=40)
    add_uv_sphere(f"{prefix}_次高光", (x + 0.10, -1.69, 5.45), (0.042, 0.011, 0.054), materials["blue_light"], collection, segments=32)


def add_foot(
    prefix: str,
    side: int,
    materials: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
) -> None:
    x = side * 0.82
    add_curve(
        f"{prefix}_小腿",
        [(x, -0.15, 0.98), (side * 0.86, -0.32, 0.62), (side * 0.90, -0.55, 0.42)],
        0.13,
        materials["orange"],
        collection,
    )
    add_uv_sphere(
        f"{prefix}_脚垫",
        (side * 0.93, -0.68, 0.24),
        (0.48, 0.19, 0.15),
        materials["orange"],
        collection,
        rotation=(0, 0, side * math.radians(-5)),
        segments=48,
    )
    for index, (toe_x, toe_z, toe_scale) in enumerate(((1.25, 0.23, 0.22), (1.10, 0.15, 0.20), (0.86, 0.13, 0.18)), start=1):
        add_uv_sphere(
            f"{prefix}_脚趾_{index}",
            (side * toe_x, -0.82, toe_z),
            (toe_scale, 0.12, 0.085),
            materials["orange"],
            collection,
            segments=36,
        )


def add_lights(collection: bpy.types.Collection) -> None:
    def area(name: str, location: tuple[float, float, float], energy: float, size: float, color: tuple[float, float, float]):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.shape = "DISK"
        data.size = size
        data.color = color
        obj = bpy.data.objects.new(name, data)
        obj.location = location
        collection.objects.link(obj)
        point_at(obj, Vector((0, 0, 3.7)))

    area("主光", (-5.5, -7.0, 9.5), 420, 5.0, (1.0, 0.88, 0.78))
    area("补光", (5.0, -5.0, 6.0), 210, 4.0, (0.68, 0.83, 1.0))
    area("轮廓光", (0.5, 4.0, 8.5), 520, 3.5, (0.52, 0.76, 1.0))


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    direction = target - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def build_scene() -> None:
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()

    model = make_collection("GUGU_MODEL")
    face = make_collection("GUGU_FACE")
    accessories = make_collection("GUGU_ACCESSORIES")
    stage = make_collection("STAGE")

    materials = {key: make_material(f"材质_{key}", value) for key, value in PALETTE.items()}
    materials["navy"].metallic = 0.0

    # 尾羽在身体之后，保证正面轮廓清晰。
    for index, (x, angle, length) in enumerate(((-0.55, -25, 1.05), (0, 0, 1.15), (0.55, 25, 1.05)), start=1):
        add_uv_sphere(
            f"尾羽_{index}",
            (x, 0.62, 2.15),
            (0.38, 0.30, length),
            materials["blue_shadow"],
            model,
            rotation=(0, math.radians(angle), 0),
            segments=48,
        )

    add_uv_sphere("身体", (0, 0, 2.61), (1.84, 1.08, 1.86), materials["blue"], model)
    add_uv_sphere("腹部", (0, -1.05, 2.53), (1.33, 0.22, 1.31), materials["cream"], model)

    add_feather_group("左翼", -1, materials, model)
    add_feather_group("右翼", 1, materials, model)

    add_uv_sphere("头部", (0, 0, 5.28), (2.15, 1.18, 1.82), materials["blue"], model)

    # 头顶三根羽冠保持独立，未来直接绑定到次级骨骼。
    crest_data = [(-0.42, 7.03, 0.25, 0.22, 0.56, -29), (0.00, 7.08, 0.28, 0.22, 0.53, 4), (0.36, 6.98, 0.22, 0.20, 0.44, 34)]
    for index, (x, z, sx, sy, sz, degrees) in enumerate(crest_data, start=1):
        add_uv_sphere(
            f"羽冠_{index}",
            (x, -0.02 + index * 0.02, z),
            (sx, sy, sz),
            materials["blue"],
            model,
            rotation=(0, math.radians(degrees), 0),
            segments=48,
        )

    # 奶油色脸颊组成连续口鼻区，保留柔软幼态感。
    add_uv_sphere("左脸颊", (-0.73, -1.10, 4.61), (1.07, 0.24, 0.60), materials["cream"], face)
    add_uv_sphere("右脸颊", (0.73, -1.10, 4.61), (1.07, 0.24, 0.60), materials["cream"], face)
    add_uv_sphere("下巴", (0, -1.14, 4.43), (0.82, 0.20, 0.43), materials["cream"], face)

    add_eye("左眼", -0.74, materials, face)
    add_eye("右眼", 0.74, materials, face)

    add_curve("左眉", [(-1.11, -1.40, 6.30), (-0.89, -1.47, 6.38), (-0.67, -1.40, 6.33)], 0.038, materials["navy"], face)
    add_curve("右眉", [(0.67, -1.40, 6.33), (0.89, -1.47, 6.38), (1.11, -1.40, 6.30)], 0.038, materials["navy"], face)

    # 张嘴微笑：橙色口缘、深色口腔、舌头与上喙均为独立表情部件。
    mouth_outer = [(-0.36, 4.75), (0.36, 4.75), (0.31, 4.43), (0.16, 4.21), (0, 4.12), (-0.16, 4.21), (-0.31, 4.43)]
    mouth_inner = [(-0.28, 4.70), (0.28, 4.70), (0.24, 4.44), (0.12, 4.28), (0, 4.21), (-0.12, 4.28), (-0.24, 4.44)]
    add_extruded_shape("嘴部外缘", mouth_outer, -1.66, 0.20, materials["orange"], face, bevel=0.065)
    add_extruded_shape("口腔", mouth_inner, -1.75, 0.08, materials["mouth"], face, bevel=0.045)
    add_uv_sphere("舌头", (0, -1.84, 4.32), (0.18, 0.025, 0.10), materials["tongue"], face, segments=40)
    beak_contour = [(-0.50, 4.91), (-0.31, 5.10), (0, 5.19), (0.31, 5.10), (0.50, 4.91), (0.27, 4.83), (0, 4.80), (-0.27, 4.83)]
    add_extruded_shape("上喙", beak_contour, -1.76, 0.28, materials["orange"], face, bevel=0.075)
    add_uv_sphere("喙高光", (-0.12, -1.84, 5.05), (0.14, 0.022, 0.050), materials["orange_light"], face, rotation=(0, 0, math.radians(-12)), segments=32)

    # 围巾主体和下沿分层，既有厚度又便于日后做飘动骨骼。
    scarf_contour = [(-1.68, 4.02), (-0.84, 3.92), (0, 3.86), (0.84, 3.92), (1.68, 4.02), (1.57, 3.65), (0.78, 3.57), (0, 3.52), (-0.78, 3.57), (-1.57, 3.65)]
    add_extruded_shape("围巾主体", scarf_contour, -1.57, 0.28, materials["scarf"], accessories, bevel=0.105)
    add_uv_sphere("围巾结", (1.68, -0.63, 3.86), (0.30, 0.20, 0.27), materials["scarf"], accessories, rotation=(0, math.radians(18), 0), segments=48)
    tail_top = [(1.72, 3.92), (2.50, 4.08), (2.92, 3.83), (2.55, 3.60), (1.78, 3.70)]
    tail_bottom = [(1.73, 3.78), (2.48, 3.66), (2.80, 3.34), (2.34, 3.20), (1.68, 3.52)]
    add_extruded_shape("围巾上尾", tail_top, -0.12, 0.22, materials["scarf"], accessories, bevel=0.10)
    add_extruded_shape("围巾下尾", tail_bottom, 0.02, 0.22, materials["scarf"], accessories, bevel=0.10)

    # 旅行挎包是品牌识别点；结构拆为带子、包体、翻盖和扣件。
    add_curve("挎包带", [(-1.35, -1.31, 4.12), (-0.65, -1.45, 3.35), (0.20, -1.52, 2.55), (1.05, -1.50, 1.95)], 0.105, materials["gold"], accessories)
    add_curve("挎包带阴影", [(-1.30, -1.43, 4.05), (-0.55, -1.58, 3.25), (0.30, -1.64, 2.45), (1.06, -1.60, 1.86)], 0.035, materials["gold_shadow"], accessories)
    add_rounded_cube("挎包包体", (1.18, -1.30, 1.72), (0.68, 0.25, 0.52), materials["gold"], accessories, rotation=(math.radians(5), 0, math.radians(-8)), bevel=0.19)
    add_rounded_cube("挎包翻盖", (1.17, -1.59, 1.90), (0.66, 0.085, 0.27), materials["gold"], accessories, rotation=(math.radians(5), 0, math.radians(-8)), bevel=0.14)
    add_uv_sphere("挎包扣", (1.23, -1.73, 1.85), (0.13, 0.05, 0.13), materials["gold_shadow"], accessories, segments=40)
    add_uv_sphere("挎包扣高光", (1.20, -1.79, 1.89), (0.060, 0.018, 0.060), materials["orange_light"], accessories, segments=32)

    add_foot("左脚", -1, materials, model)
    add_foot("右脚", 1, materials, model)

    # 舞台、相机与柔光形成接近应用插画的 2.5D 正面表现。
    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 1.8, 0))
    ground = bpy.context.object
    ground.name = "地面"
    assign_material(ground, materials["ground"])
    move_to_collection(ground, stage)

    camera_data = bpy.data.cameras.new("正面相机")
    camera = bpy.data.objects.new("正面相机", camera_data)
    stage.objects.link(camera)
    camera.location = (0, -18.0, 4.15)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 9.05
    camera_data.lens = 58
    point_at(camera, Vector((0, 0, 4.05)))
    bpy.context.scene.camera = camera
    add_lights(stage)

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = str(TRANSPARENT_RENDER_PATH)
    scene.render.use_file_extension = True
    scene.render.use_freestyle = False
    scene.render.line_thickness = 1.15
    line_style = bpy.context.view_layer.freestyle_settings.linesets[0].linestyle
    line_style.color = srgb(PALETTE["navy"])[:3]
    line_style.thickness = 1.65
    world = scene.world or bpy.data.worlds.new("品牌世界")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = srgb("F7F4EF")
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.48
    scene.view_settings.view_transform = "Standard"
    try:
        scene.view_settings.look = "Medium High Contrast"
    except TypeError:
        pass

    # 统一标记导出语义，后续骨骼和 USDZ 流程按这些集合工作。
    for obj in model.objects:
        obj["gugu_role"] = "deformable"
    for obj in face.objects:
        obj["gugu_role"] = "facial"
    for obj in accessories.objects:
        obj["gugu_role"] = "accessory"

    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    bpy.ops.render.render(write_still=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND_PATH))
    print(f"GUGU_MODEL_SAVED={BLEND_PATH}")
    print(f"GUGU_RENDER_SAVED={TRANSPARENT_RENDER_PATH}")


if __name__ == "__main__":
    build_scene()
