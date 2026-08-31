"""依据审核后的三视图契约，确定性构建咕咕 v3 角色模型。"""

from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[3]
MODEL_DIR = ROOT / "Assets/Brand/Model/source"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"
PRIMARY_BLEND = MODEL_DIR / "gugu-v3-stage-10-primary-forms.blend"
COMPLETE_BLOCKOUT_BLEND = MODEL_DIR / "gugu-v3-stage-20-complete-blockout.blend"
SECONDARY_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-30-secondary-refined.blend"
FORM_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-40-form-refined.blend"
DETAIL_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-50-detail-refined.blend"
STATIC_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-60-static-final.blend"
LOOKDEV_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-70-lookdev-final.blend"
POLISHED_FORM_BLEND = MODEL_DIR / "gugu-v3-stage-80-polished-form.blend"
PRODUCTION_CANDIDATE_BLEND = MODEL_DIR / "gugu-v3-stage-90-production-candidate.blend"
MATERIAL_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-100-material-refined.blend"
DEPTH_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-110-depth-refined.blend"
SURFACE_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-120-surface-refined.blend"
DETAIL_VOLUME_BLEND = MODEL_DIR / "gugu-v3-stage-130-detail-volume.blend"
HERO_FORM_BLEND = MODEL_DIR / "gugu-v3-stage-140-hero-form.blend"
STATIC_QA_BLEND = MODEL_DIR / "gugu-v3-stage-150-static-qa.blend"
DEPTH_CORRECTED_BLEND = MODEL_DIR / "gugu-v3-stage-160-depth-corrected.blend"
FINAL_REFINED_BLEND = MODEL_DIR / "gugu-v3-stage-170-final-refined.blend"
MULTIVIEW_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-180-multiview-final.blend"
ANIMATION_FACE_BLEND = MODEL_DIR / "gugu-v3-stage-190-animation-face.blend"
TOPOLOGY_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-200-topology-final.blend"
TOPOLOGY_CLOSED_BLEND = MODEL_DIR / "gugu-v3-stage-210-topology-closed.blend"
SHADING_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-220-shading-final.blend"
DELIVERY_FINAL_BLEND = MODEL_DIR / "gugu-v3-stage-230-delivery-final.blend"
PX = 7.0 / 571.0
IMAGE_WIDTH = 540
IMAGE_HEIGHT = 887
FRONT_CENTER_X = 270.0
FLOOR_Y = 720.0
SIDE_CENTER_X = 261.5


PALETTE = {
    "blue": "43B8F2",
    "blue_shadow": "258FC7",
    "cream": "FFF0C6",
    "navy": "082A4D",
    "orange": "FF8448",
    "red": "F05A4D",
    "red_shadow": "C93635",
    "gold": "F5B51D",
    "gold_shadow": "CF8308",
    "white": "FFFDF7",
    "ground": "F5F1EA",
    "eye_navy": "061F3A",
    "eye_blue": "1474AD",
    "eye_white": "FFFFFF",
}

MATERIAL_PROFILES = {
    "blue": (0.47, 0.05, 0.04),
    "blue_shadow": (0.50, 0.03, 0.035),
    "cream": (0.54, 0.08, 0.035),
    "navy": (0.43, 0.01, 0.06),
    "orange": (0.37, 0.035, 0.10),
    "red": (0.66, 0.025, 0.025),
    "red_shadow": (0.68, 0.02, 0.02),
    "gold": (0.34, 0.02, 0.16),
    "gold_shadow": (0.40, 0.015, 0.10),
    "white": (0.48, 0.02, 0.05),
    "ground": (0.72, 0.0, 0.0),
    "eye_navy": (0.11, 0.0, 0.30),
    "eye_blue": (0.14, 0.0, 0.26),
    "eye_white": (0.16, 0.01, 0.22),
}


def parse_stage() -> str:
    if "--" not in sys.argv:
        return "primary"
    args = sys.argv[sys.argv.index("--") + 1 :]
    if "--stage" in args:
        return args[args.index("--stage") + 1]
    return "primary"


def world_z(pixel_y: float) -> float:
    return (FLOOR_Y - pixel_y) * PX


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)


def make_collection(name: str) -> bpy.types.Collection:
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def hex_color(value: str) -> tuple[float, float, float, float]:
    value = value.lstrip("#")
    srgb = [int(value[index : index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4 for channel in srgb]
    return tuple(linear) + (1.0,)


def make_material(
    name: str,
    color: str,
    roughness: float = 0.58,
    subsurface: float = 0.04,
    coat: float = 0.04,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = hex_color(color)
    material.use_nodes = True
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = hex_color(color)
    shader.inputs["Roughness"].default_value = roughness
    if "Coat Weight" in shader.inputs:
        shader.inputs["Coat Weight"].default_value = coat
        shader.inputs["Coat Roughness"].default_value = max(0.08, roughness * 0.55)
    if "Subsurface Weight" in shader.inputs:
        shader.inputs["Subsurface Weight"].default_value = subsurface
        if "Subsurface Radius" in shader.inputs:
            shader.inputs["Subsurface Radius"].default_value = (0.65, 0.42, 0.28)
    return material


def signed_power(value: float, power: float) -> float:
    if value == 0.0:
        return 0.0
    return math.copysign(abs(value) ** power, value)


def add_subdivision(obj: bpy.types.Object, viewport: int = 1, render: int = 2) -> None:
    modifier = obj.modifiers.new("细分曲面", "SUBSURF")
    modifier.subdivision_type = "CATMULL_CLARK"
    modifier.levels = viewport
    modifier.render_levels = render


def create_loft(
    name: str,
    rings: list[dict[str, float]],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    segments: int = 48,
    exponent: float = 2.35,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    power = 2.0 / exponent

    for ring in rings:
        center_y = (ring["front"] + ring["back"]) * 0.5
        radius_y = (ring["back"] - ring["front"]) * 0.5
        for index in range(segments):
            angle = math.tau * index / segments
            cosine = math.cos(angle)
            sine = math.sin(angle)
            x_normalized = signed_power(cosine, power)
            y_normalized = signed_power(sine, power)
            x = ring.get("x", 0.0) + ring["rx"] * x_normalized
            y = center_y + radius_y * y_normalized
            # 前脸保留宽缓、略向后收的面片，避免标准椭球的强球面高光。
            if y_normalized < -0.35:
                edge = abs(x_normalized)
                plane_y = ring["front"] + ring.get("face_curve", 0.14) * edge * edge
                blend = min(1.0, (-y_normalized - 0.35) / 0.65)
                y = y * (1.0 - blend) + plane_y * blend
            vertices.append((x, y, ring["z"]))

    ring_count = len(rings)
    for ring_index in range(ring_count - 1):
        start = ring_index * segments
        next_start = (ring_index + 1) * segments
        for index in range(segments):
            following = (index + 1) % segments
            faces.append((start + index, start + following, next_start + following, next_start + index))

    bottom_center = len(vertices)
    bottom = rings[0]
    vertices.append((bottom.get("x", 0.0), (bottom["front"] + bottom["back"]) * 0.5, bottom["z"]))
    top_center = len(vertices)
    top = rings[-1]
    vertices.append((top.get("x", 0.0), (top["front"] + top["back"]) * 0.5, top["z"]))
    for index in range(segments):
        following = (index + 1) % segments
        faces.append((bottom_center, following, index))
        top_start = (ring_count - 1) * segments
        faces.append((top_center, top_start + index, top_start + following))

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    add_subdivision(obj)
    return obj


def px_radius(value: float) -> float:
    return value * PX


def pixel_point(x: float, y: float, depth: float = 0.0) -> Vector:
    return Vector(((x - FRONT_CENTER_X) * PX, depth, world_z(y)))


def join_objects(name: str, objects: list[bpy.types.Object]) -> bpy.types.Object:
    if not objects:
        raise RuntimeError(f"没有可合并对象：{name}")
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    return result


def apply_all_modifiers(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)


def bake_object_transform(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def close_mesh_boundaries(obj: bpy.types.Object) -> None:
    """封闭曲线转网格后残留的端口/边界环。"""
    if obj.type != "MESH":
        return
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(8):
        boundary = [edge for edge in bm.edges if len(edge.link_faces) == 1]
        if not boundary:
            break
        bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
    remaining = [edge for edge in bm.edges if len(edge.link_faces) == 1]
    unvisited = set(remaining)
    while unvisited:
        seed = unvisited.pop()
        component = {seed}
        stack = [seed]
        while stack:
            edge = stack.pop()
            for vertex in edge.verts:
                for linked in vertex.link_edges:
                    if linked in unvisited and len(linked.link_faces) == 1:
                        unvisited.remove(linked)
                        component.add(linked)
                        stack.append(linked)
        component_vertices = {vertex for edge in component for vertex in edge.verts}
        center = sum((vertex.co for vertex in component_vertices), Vector()) / len(component_vertices)
        center_vertex = bm.verts.new(center)
        for edge in component:
            try:
                bm.faces.new((edge.verts[0], edge.verts[1], center_vertex))
            except ValueError:
                pass
    if remaining:
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    if remaining:
        remaining = [edge for edge in bm.edges if len(edge.link_faces) == 1]
        if remaining:
            bm.free()
            raise RuntimeError(f"曲线网格封口失败：{obj.name}，剩余边界 {len(remaining)}")
    bm.to_mesh(obj.data)
    obj.data.update()
    bm.free()


def apply_character_world_depth_scale(factor: float) -> None:
    """只压缩角色世界 Y 深度，保持正面/背面 X-Z 契约不变。"""
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.name.startswith(("CHR_", "ACC_", "DEC_")):
            continue
        world_matrix = obj.matrix_world.copy()
        inverse = world_matrix.inverted()
        for vertex in obj.data.vertices:
            world = world_matrix @ vertex.co
            world.y *= factor
            vertex.co = inverse @ world


def transform_named_meshes_world(
    names: set[str],
    *,
    y_scale: float = 1.0,
    y_anchor: float = 0.0,
    y_offset: float = 0.0,
    x_offset: float = 0.0,
    z_offset: float = 0.0,
) -> None:
    """对指定部件做世界坐标局部修形，供多视图闭环使用。"""
    for name in names:
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            continue
        world_matrix = obj.matrix_world.copy()
        inverse = world_matrix.inverted()
        for vertex in obj.data.vertices:
            world = world_matrix @ vertex.co
            world.x += x_offset
            world.y = y_anchor + (world.y - y_anchor) * y_scale + y_offset
            world.z += z_offset
            vertex.co = inverse @ world


def rotate_around_pivot_preserve_front(
    obj: bpy.types.Object,
    pivot: Vector,
    angle: float,
    *,
    front_scale: float = 1.0,
) -> None:
    apply_all_modifiers(obj)
    bake_object_transform(obj)
    cosine = math.cos(angle)
    for vertex in obj.data.vertices:
        local = vertex.co - pivot
        local.x *= front_scale / max(abs(cosine), 1e-6)
        vertex.co = local
    obj.location = pivot
    obj.rotation_euler.z = angle


def add_ellipsoid(
    name: str,
    location: tuple[float, float, float],
    scale: tuple[float, float, float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    segments: int = 40,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=segments,
        ring_count=max(20, segments // 2),
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def add_curve_mesh(
    name: str,
    points: list[tuple[float, float, float]],
    bevel_depth: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    bevel_resolution: int = 5,
    cyclic: bool = False,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 16
    curve.bevel_depth = bevel_depth
    curve.bevel_resolution = bevel_resolution
    curve.use_fill_caps = True
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(points) - 1)
    for point, coordinate in zip(spline.bezier_points, points):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    spline.use_cyclic_u = cyclic
    obj = bpy.data.objects.new(name, curve)
    collection.objects.link(obj)
    curve.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    bake_object_transform(obj)
    close_mesh_boundaries(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
        if abs(polygon.normal.y) > 0.82:
            polygon.use_smooth = False
    return obj


def create_contour_volume(
    name: str,
    contour_px: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    back_scale: float = 0.90,
    bevel: float = 0.035,
) -> bpy.types.Object:
    front = [pixel_point(x, y, front_y) for x, y in contour_px]
    center = sum(front, Vector()) / len(front)
    back = [Vector((center.x + (point.x - center.x) * back_scale, back_y, center.z + (point.z - center.z) * back_scale)) for point in front]
    vertices = [tuple(point) for point in front + back]
    count = len(front)
    faces: list[tuple[int, ...]] = [tuple(reversed(range(count))), tuple(range(count, count * 2))]
    for index in range(count):
        following = (index + 1) % count
        faces.append((index, following, count + following, count + index))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    modifier = obj.modifiers.new("柔化边缘", "BEVEL")
    modifier.width = bevel
    modifier.segments = 4
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def create_bezier_contour_volume(
    name: str,
    contour_px: list[tuple[float, float]],
    front_y: float,
    back_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    bevel: float = 0.045,
) -> bpy.types.Object:
    curve = bpy.data.curves.new(f"{name}_Curve", "CURVE")
    curve.dimensions = "2D"
    curve.resolution_u = 20
    curve.resolution_v = 6
    curve.fill_mode = "BOTH"
    thickness = max(0.02, back_y - front_y)
    curve.extrude = max(0.005, thickness * 0.5 - bevel)
    curve.bevel_depth = min(bevel, thickness * 0.45)
    curve.bevel_resolution = 5
    spline = curve.splines.new("BEZIER")
    spline.bezier_points.add(len(contour_px) - 1)
    for point, (x, y) in zip(spline.bezier_points, contour_px):
        world = pixel_point(x, y)
        point.co = (world.x, world.z, 0.0)
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"
    spline.use_cyclic_u = True
    obj = bpy.data.objects.new(name, curve)
    obj.location.y = (front_y + back_y) * 0.5
    obj.rotation_euler.x = math.pi / 2.0
    collection.objects.link(obj)
    curve.materials.append(material)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target="MESH")
    obj = bpy.context.object
    obj.name = name
    bake_object_transform(obj)
    close_mesh_boundaries(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
        if abs(polygon.normal.y) > 0.82:
            polygon.use_smooth = False
    return obj


def smooth_closed_contour(points: list[Vector], iterations: int = 2) -> list[Vector]:
    """用 Chaikin 细分把人工落点变成稳定的封闭软轮廓。"""
    result = points
    for _ in range(iterations):
        refined: list[Vector] = []
        for index, current in enumerate(result):
            following = result[(index + 1) % len(result)]
            refined.append(current * 0.75 + following * 0.25)
            refined.append(current * 0.25 + following * 0.75)
        result = refined
    return result


def create_domed_contour_volume(
    name: str,
    contour_px: list[tuple[float, float]],
    rim_y: float,
    back_y: float,
    dome_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    inner_scales: tuple[float, ...] = (0.78, 0.46),
    smooth_iterations: int = 2,
) -> bpy.types.Object:
    """从正面轮廓生成封闭的软体曲面，避免贴片式平面挤出。"""
    boundary = smooth_closed_contour([pixel_point(x, y, rim_y) for x, y in contour_px], iterations=smooth_iterations)
    center = sum(boundary, Vector()) / len(boundary)
    rings: list[list[Vector]] = [boundary]
    for ring_index, scale in enumerate(inner_scales, start=1):
        amount = ring_index / (len(inner_scales) + 1)
        y = rim_y + (dome_y - rim_y) * math.sin(amount * math.pi * 0.5)
        rings.append(
            [Vector((center.x + (point.x - center.x) * scale, y, center.z + (point.z - center.z) * scale)) for point in boundary]
        )

    vertices: list[tuple[float, float, float]] = []
    for ring in rings:
        vertices.extend(tuple(point) for point in ring)
    front_center = len(vertices)
    vertices.append((center.x, dome_y, center.z))
    back_start = len(vertices)
    vertices.extend((point.x, back_y, point.z) for point in boundary)
    back_center = len(vertices)
    vertices.append((center.x, back_y, center.z))

    count = len(boundary)
    faces: list[tuple[int, ...]] = []
    for ring_index in range(len(rings) - 1):
        start = ring_index * count
        following_start = (ring_index + 1) * count
        for index in range(count):
            following = (index + 1) % count
            faces.append((start + index, start + following, following_start + following, following_start + index))
    inner_start = (len(rings) - 1) * count
    for index in range(count):
        following = (index + 1) % count
        faces.append((inner_start + index, inner_start + following, front_center))
        faces.append((index, back_start + index, back_start + following, following))
        faces.append((back_start + index, back_center, back_start + following))

    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("软体边缘", "BEVEL")
    bevel.width = 0.018
    bevel.segments = 2
    return obj


def create_radial_wedge(
    name: str,
    contour_px: list[tuple[float, float]],
    tip_y: float,
    base_y: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    boundary = [pixel_point(x, y, base_y) for x, y in contour_px]
    center = sum(boundary, Vector()) / len(boundary)
    tip = Vector((center.x, tip_y, center.z))
    back_y = base_y + 0.10
    back = [Vector((point.x, back_y, point.z)) for point in boundary]
    vertices = [tuple(point) for point in boundary] + [tuple(tip)] + [tuple(point) for point in back]
    count = len(boundary)
    tip_index = count
    back_start = count + 1
    faces: list[tuple[int, ...]] = []
    for index in range(count):
        following = (index + 1) % count
        faces.append((tip_index, index, following))
        faces.append((index, back_start + index, back_start + following, following))
    faces.append(tuple(back_start + index for index in reversed(range(count))))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    modifier = obj.modifiers.new("鸟喙柔化", "BEVEL")
    modifier.width = 0.035
    modifier.segments = 4
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    return obj


def create_feather_mesh(
    name: str,
    centers: list[Vector],
    widths: list[float],
    thickness: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    thickness_axis: Vector,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    for index, (center, width) in enumerate(zip(centers, widths)):
        before = centers[max(0, index - 1)]
        after = centers[min(len(centers) - 1, index + 1)]
        tangent = (after - before).normalized()
        axis = thickness_axis.normalized()
        width_axis = axis.cross(tangent).normalized()
        for width_sign, thickness_sign in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            point = center + width_axis * width * width_sign + axis * thickness * thickness_sign
            vertices.append(tuple(point))
    faces: list[tuple[int, ...]] = []
    for section in range(len(centers) - 1):
        start = section * 4
        following = (section + 1) * 4
        for side in range(4):
            next_side = (side + 1) % 4
            faces.append((start + side, start + next_side, following + next_side, following + side))
    faces.append((3, 2, 1, 0))
    end = (len(centers) - 1) * 4
    faces.append((end, end + 1, end + 2, end + 3))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    add_subdivision(obj, viewport=1, render=2)
    return obj


def add_torus(
    name: str,
    location: tuple[float, float, float],
    major_radius: float,
    minor_radius: float,
    material: bpy.types.Material,
    collection: bpy.types.Collection,
    *,
    rotation: tuple[float, float, float] = (math.pi / 2.0, 0.0, 0.0),
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=48,
        minor_segments=12,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(material)
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    collection.objects.link(obj)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    return obj


def build_primary_forms(materials: dict[str, bpy.types.Material], geo: bpy.types.Collection) -> list[bpy.types.Object]:
    # 头壳：宽度来自正面图，前后深度来自清理后的侧面主体，不采用球体缩放。
    head_data = [
        # pixel_y, half_width_px, front_depth_px, back_depth_px, face_curve_world
        (444, 40, 78, 66, 0.07),
        (430, 78, 104, 86, 0.09),
        (410, 108, 122, 98, 0.11),
        (385, 126, 132, 105, 0.13),
        (350, 138, 138, 108, 0.14),
        (315, 142, 140, 108, 0.145),
        (280, 138, 135, 105, 0.14),
        (245, 125, 122, 98, 0.125),
        (220, 103, 103, 84, 0.105),
        (202, 67, 72, 62, 0.08),
        (194, 24, 28, 25, 0.04),
    ]
    head_rings = [
        {
            "z": world_z(py),
            "rx": px_radius(rx),
            "front": -px_radius(front),
            "back": px_radius(back),
            "face_curve": curve,
            "x": px_radius(15),
        }
        for py, rx, front, back, curve in head_data
    ]
    head = create_loft("CHR_GUGU_Head", head_rings, materials["blue"], geo, exponent=2.10)

    torso_data = [
        (661, 28, 54, 66, 0.04),
        (653, 68, 80, 92, 0.06),
        (636, 103, 100, 119, 0.08),
        (615, 132, 130, 145, 0.10),
        (575, 148, 142, 156, 0.12),
        (535, 151, 140, 162, 0.13),
        (495, 142, 132, 154, 0.12),
        (460, 119, 112, 136, 0.10),
        (438, 88, 92, 110, 0.075),
        (425, 48, 61, 73, 0.05),
    ]
    torso_rings = [
        {
            "z": world_z(py),
            "rx": px_radius(rx),
            "front": -px_radius(front),
            "back": px_radius(back),
            "face_curve": curve,
            "x": px_radius(5),
        }
        for py, rx, front, back, curve in torso_data
    ]
    torso = create_loft("CHR_GUGU_Torso", torso_rings, materials["blue"], geo, exponent=2.08)
    return [head, torso]


def create_scarf_wrap(material: bpy.types.Material, shadow_material: bpy.types.Material, collection: bpy.types.Collection) -> bpy.types.Object:
    segments = 64
    cross_segments = 10
    center_x = px_radius(17)
    radius_x = px_radius(128)
    radius_y = px_radius(124)
    # 三条相互压叠的扁带共同组成一条围巾，避免圆管/救生圈感。
    band_specs = [
        (world_z(458), 0.105, 0.155, 0.00, 1),
        (world_z(446), 0.115, 0.165, -0.025, 0),
        (world_z(433), 0.100, 0.150, 0.015, 0),
    ]
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, int, int, int]] = []
    face_materials: list[int] = []
    for band_index, (center_z, radial_half, vertical_half, radial_offset, material_index) in enumerate(band_specs):
        band_start = len(vertices)
        for index in range(segments):
            angle = math.tau * index / segments
            center = Vector(
                (
                    center_x + (radius_x + radial_offset) * math.cos(angle),
                    (radius_y + radial_offset) * math.sin(angle),
                    center_z + 0.018 * math.sin(angle * 2.0 + band_index),
                )
            )
            radial = Vector((math.cos(angle), math.sin(angle), 0.0))
            for cross_index in range(cross_segments):
                cross_angle = math.tau * cross_index / cross_segments
                point = center + radial * (radial_half * math.cos(cross_angle))
                point.z += vertical_half * math.sin(cross_angle)
                vertices.append(tuple(point))
        for index in range(segments):
            following = (index + 1) % segments
            for cross_index in range(cross_segments):
                next_cross = (cross_index + 1) % cross_segments
                a = band_start + index * cross_segments + cross_index
                b = band_start + index * cross_segments + next_cross
                c = band_start + following * cross_segments + next_cross
                d = band_start + following * cross_segments + cross_index
                faces.append((a, b, c, d))
                face_materials.append(material_index)
    mesh = bpy.data.meshes.new("ACC_GUGU_Scarf_Wrap_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("ACC_GUGU_Scarf_Wrap", mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    mesh.materials.append(shadow_material)
    for polygon, material_index in zip(mesh.polygons, face_materials):
        polygon.use_smooth = True
        polygon.material_index = material_index
    add_subdivision(obj, viewport=1, render=1)
    return obj


def build_eye(
    name: str,
    x: float,
    z: float,
    materials: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
    *,
    mirror: float,
) -> bpy.types.Object:
    parts = [
        add_ellipsoid(f"{name}_深色眼圈", (x, -1.46, z), (0.48, 0.105, 0.63), materials["eye_navy"], collection),
        add_ellipsoid(f"{name}_眼白", (x, -1.52, z), (0.425, 0.075, 0.565), materials["eye_white"], collection),
        add_ellipsoid(f"{name}_虹膜", (x, -1.585, z - 0.015), (0.335, 0.042, 0.455), materials["eye_blue"], collection),
        add_ellipsoid(f"{name}_瞳孔", (x, -1.62, z + 0.005), (0.275, 0.026, 0.395), materials["eye_navy"], collection),
        add_ellipsoid(f"{name}_主高光", (x - 0.095 * mirror, -1.655, z + 0.205), (0.090, 0.012, 0.125), materials["eye_white"], collection, segments=28),
        add_ellipsoid(f"{name}_次高光", (x + 0.115 * mirror, -1.655, z - 0.125), (0.040, 0.010, 0.058), materials["eye_white"], collection, segments=24),
    ]
    return join_objects(name, parts)


def build_foot(
    name: str,
    x: float,
    materials: dict[str, bpy.types.Material],
    collection: bpy.types.Collection,
    *,
    side: float,
) -> bpy.types.Object:
    parts = [
        add_ellipsoid(f"{name}_脚垫", (x, -0.16, 0.13), (0.27, 0.25, 0.13), materials["orange"], collection, segments=32),
    ]
    toe_offsets = [(-0.25, -0.48, 0.14, -18.0), (0.0, -0.64, 0.15, 0.0), (0.25, -0.48, 0.14, 18.0)]
    for index, (offset_x, y, radius, yaw) in enumerate(toe_offsets, start=1):
        parts.append(
            add_ellipsoid(
                f"{name}_趾_{index}",
                (x + offset_x, y, 0.105),
                (radius * 1.12, 0.33, 0.12),
                materials["orange"],
                collection,
                rotation=(0.0, 0.0, side * math.radians(yaw)),
                segments=28,
            )
        )
    return join_objects(name, parts)


def create_tapered_leg(
    name: str,
    centers: list[Vector],
    radii: list[float],
    material: bpy.types.Material,
    collection: bpy.types.Collection,
) -> bpy.types.Object:
    """建立带踝部弯折和上下锥度的圆腿。"""
    segments = 20
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for center, radius in zip(centers, radii):
        for index in range(segments):
            angle = math.tau * index / segments
            vertices.append((center.x + math.cos(angle) * radius, center.y + math.sin(angle) * radius, center.z))
    for ring_index in range(len(centers) - 1):
        start = ring_index * segments
        following_start = (ring_index + 1) * segments
        for index in range(segments):
            following = (index + 1) % segments
            faces.append((start + index, start + following, following_start + following, following_start + index))
    bottom_center = len(vertices)
    vertices.append(tuple(centers[0]))
    top_center = len(vertices)
    vertices.append(tuple(centers[-1]))
    for index in range(segments):
        following = (index + 1) % segments
        faces.append((bottom_center, following, index))
        top_start = (len(centers) - 1) * segments
        faces.append((top_center, top_start + index, top_start + following))
    mesh = bpy.data.meshes.new(f"{name}_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    mesh.materials.append(material)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    add_subdivision(obj, viewport=1, render=2)
    return obj


def build_secondary_forms(
    materials: dict[str, bpy.types.Material],
    geo: bpy.types.Collection,
    face: bpy.types.Collection,
    accessories: bpy.types.Collection,
    decals: bpy.types.Collection,
) -> list[bpy.types.Object]:
    structural: list[bpy.types.Object] = []

    crest_specs = [
        ("CHR_GUGU_Crest_A", [(286, 211), (277, 190), (280, 166), (290, 150)], [0.17, 0.24, 0.19, 0.07], [-0.35, -0.60, -0.90, -1.10]),
        ("CHR_GUGU_Crest_B", [(299, 216), (312, 199), (336, 181)], [0.16, 0.22, 0.07], [-0.25, -0.55, -0.85]),
        ("CHR_GUGU_Crest_C", [(310, 220), (333, 209), (356, 195)], [0.14, 0.19, 0.065], [-0.15, -0.40, -0.65]),
    ]
    for name, point_specs, widths, depths in crest_specs:
        centers = [pixel_point(x, y, depth) for (x, y), depth in zip(point_specs, depths)]
        structural.append(create_feather_mesh(name, centers, widths, 0.11, materials["blue"], geo, thickness_axis=Vector((0, 1, 0))))

    eye_r = build_eye("CHR_GUGU_Eye.R", (217 - FRONT_CENTER_X) * PX, world_z(337), materials, face, mirror=1.0)
    eye_l = build_eye("CHR_GUGU_Eye.L", (358 - FRONT_CENTER_X) * PX, world_z(337), materials, face, mirror=-1.0)
    structural.extend([eye_r, eye_l])

    structural.append(
        add_curve_mesh(
            "CHR_GUGU_Brow.R",
            [tuple(pixel_point(x, y, -1.62)) for x, y in [(195, 281), (205, 270), (217, 265), (229, 269), (239, 280)]],
            0.038,
            materials["navy"],
            face,
        )
    )
    structural.append(
        add_curve_mesh(
            "CHR_GUGU_Brow.L",
            [tuple(pixel_point(x, y, -1.62)) for x, y in [(336, 280), (347, 269), (359, 264), (371, 269), (382, 281)]],
            0.038,
            materials["navy"],
            face,
        )
    )

    cheek_r = [
        (158, 384), (162, 375), (175, 366), (195, 361), (216, 361), (236, 365),
        (255, 372), (274, 379), (285, 384), (285, 430), (272, 435), (260, 438),
        (240, 440), (226, 438), (205, 436), (181, 428), (164, 418), (160, 410),
    ]
    cheek_l = [
        (285, 384), (298, 379), (311, 371), (331, 365), (354, 361), (376, 362),
        (396, 367), (409, 376), (414, 386), (411, 410), (406, 419), (394, 428),
        (373, 436), (351, 440), (330, 438), (310, 435), (298, 432), (285, 430),
    ]
    structural.append(
        create_domed_contour_volume(
            "CHR_GUGU_CheekPad.R", cheek_r, -1.46, -1.26, -1.70, materials["cream"], face, smooth_iterations=0
        )
    )
    structural.append(
        create_domed_contour_volume(
            "CHR_GUGU_CheekPad.L", cheek_l, -1.46, -1.26, -1.70, materials["cream"], face, smooth_iterations=0
        )
    )

    beak_upper = [(247, 374), (256, 352), (281, 343), (310, 353), (324, 374), (285, 391)]
    beak_lower = [(252, 379), (285, 390), (319, 379), (313, 403), (285, 419), (258, 404)]
    structural.append(create_radial_wedge("CHR_GUGU_Beak_Upper", beak_upper, -2.38, -1.55, materials["orange"], face))
    structural.append(create_radial_wedge("CHR_GUGU_Beak_Lower", beak_lower, -2.16, -1.54, materials["orange"], face))
    nostrils = [
        add_ellipsoid("鼻孔_R", tuple(pixel_point(268, 366, -2.13)), (0.030, 0.016, 0.018), materials["navy"], decals, segments=20),
        add_ellipsoid("鼻孔_L", tuple(pixel_point(303, 366, -2.13)), (0.030, 0.016, 0.018), materials["navy"], decals, segments=20),
    ]
    join_objects("DEC_GUGU_BeakNostril.LR", nostrils)

    wing_r = [
        (156, 442), (130, 450), (108, 482), (90, 522), (72, 560),
        (52, 603), (72, 599), (82, 613), (99, 603),
        (112, 610), (130, 594),
        (151, 576), (166, 544), (183, 502), (178, 466),
    ]
    wing_l = [
        (389, 442), (417, 451), (440, 482), (457, 520), (473, 558),
        (487, 603), (467, 599), (457, 613), (440, 603),
        (427, 610), (409, 594),
        (392, 574), (382, 542), (376, 500),
    ]
    wing_r_obj = create_domed_contour_volume("右翼基础", wing_r, -1.34, -1.10, -1.55, materials["blue"], geo)
    wing_l_obj = create_domed_contour_volume("左翼基础", wing_l, -1.34, -1.10, -1.55, materials["blue"], geo)
    wing_r_obj.name = "CHR_GUGU_Wing.R"
    wing_l_obj.name = "CHR_GUGU_Wing.L"
    wing_r_pivot = pixel_point(162, 455, -1.40)
    wing_l_pivot = pixel_point(394, 455, -1.40)
    wing_angle = math.radians(36)
    rotate_around_pivot_preserve_front(wing_r_obj, wing_r_pivot, -wing_angle, front_scale=0.95)
    rotate_around_pivot_preserve_front(wing_l_obj, wing_l_pivot, wing_angle, front_scale=0.95)
    structural.extend([wing_r_obj, wing_l_obj])

    wing_r_feather_specs = [
        [(130, 495), (151, 510), (148, 545), (125, 578), (95, 599), (82, 585), (100, 550)],
        [(109, 520), (132, 540), (123, 573), (99, 602), (75, 612), (62, 598), (82, 566)],
    ]
    wing_l_feather_specs = [[(IMAGE_WIDTH - x, y) for x, y in points] for points in wing_r_feather_specs]
    for index, points in enumerate(wing_r_feather_specs, start=1):
        feather = create_domed_contour_volume(
            f"DEC_GUGU_WingLayer.R.{index}", points, -1.53, -1.46, -1.60, materials["blue"], decals, inner_scales=(0.76, 0.46)
        )
        rotate_around_pivot_preserve_front(feather, wing_r_pivot, -wing_angle, front_scale=0.95)
    for index, points in enumerate(wing_l_feather_specs, start=1):
        feather = create_domed_contour_volume(
            f"DEC_GUGU_WingLayer.L.{index}", points, -1.53, -1.46, -1.60, materials["blue"], decals, inner_scales=(0.76, 0.46)
        )
        rotate_around_pivot_preserve_front(feather, wing_l_pivot, wing_angle, front_scale=0.95)
    wing_r_groove_parts = [
        add_curve_mesh("右翼羽沟_1", [tuple(pixel_point(x, y, -1.73)) for x, y in [(148, 500), (126, 548), (92, 586)]], 0.011, materials["blue_shadow"], decals),
        add_curve_mesh("右翼羽沟_2", [tuple(pixel_point(x, y, -1.73)) for x, y in [(158, 525), (149, 563), (126, 593)]], 0.010, materials["blue_shadow"], decals),
    ]
    wing_l_groove_parts = [
        add_curve_mesh("左翼羽沟_1", [tuple(pixel_point(x, y, -1.73)) for x, y in [(397, 500), (419, 548), (466, 586)]], 0.011, materials["blue_shadow"], decals),
        add_curve_mesh("左翼羽沟_2", [tuple(pixel_point(x, y, -1.73)) for x, y in [(387, 525), (396, 563), (419, 593)]], 0.010, materials["blue_shadow"], decals),
    ]
    wing_r_groove = join_objects("DEC_GUGU_WingFeatherDetail.R", wing_r_groove_parts)
    wing_l_groove = join_objects("DEC_GUGU_WingFeatherDetail.L", wing_l_groove_parts)
    rotate_around_pivot_preserve_front(wing_r_groove, wing_r_pivot, -wing_angle, front_scale=0.95)
    rotate_around_pivot_preserve_front(wing_l_groove, wing_l_pivot, wing_angle, front_scale=0.95)

    tail_parts = [
        create_feather_mesh("尾羽_A", [Vector((-0.35, 1.05, 1.02)), Vector((-0.52, 1.62, 1.16)), Vector((-0.72, 2.08, 1.28))], [0.18, 0.32, 0.10], 0.14, materials["blue_shadow"], geo, thickness_axis=Vector((1, 0, 0))),
        create_feather_mesh("尾羽_B", [Vector((0.10, 1.10, 0.98)), Vector((0.10, 1.74, 1.10)), Vector((0.06, 2.28, 1.18))], [0.20, 0.36, 0.11], 0.14, materials["blue"], geo, thickness_axis=Vector((1, 0, 0))),
        create_feather_mesh("尾羽_C", [Vector((0.52, 1.02, 1.05)), Vector((0.68, 1.60, 1.20)), Vector((0.84, 2.06, 1.35))], [0.18, 0.32, 0.10], 0.14, materials["blue_shadow"], geo, thickness_axis=Vector((1, 0, 0))),
    ]
    structural.append(join_objects("CHR_GUGU_Tail", tail_parts))
    tail_cover = [(232, 631), (247, 617), (265, 621), (282, 610), (300, 620), (320, 628), (314, 643), (296, 652), (277, 648), (258, 654), (238, 646)]
    create_domed_contour_volume(
        "DEC_GUGU_TailCover",
        tail_cover,
        2.02,
        1.82,
        2.30,
        materials["blue"],
        decals,
        inner_scales=(0.75, 0.42),
    )

    leg_r = create_tapered_leg(
        "CHR_GUGU_Leg.R",
        [Vector((-0.69, -0.02, 0.88)), Vector((-0.71, -0.13, 0.52)), Vector((-0.68, -0.22, 0.21))],
        [0.12, 0.10, 0.085],
        materials["orange"],
        geo,
    )
    leg_l = create_tapered_leg(
        "CHR_GUGU_Leg.L",
        [Vector((0.87, -0.02, 0.88)), Vector((0.85, -0.13, 0.52)), Vector((0.84, -0.22, 0.21))],
        [0.12, 0.10, 0.085],
        materials["orange"],
        geo,
    )
    structural.extend([leg_r, leg_l])
    structural.append(build_foot("CHR_GUGU_Foot.R", -0.69, materials, geo, side=-1.0))
    structural.append(build_foot("CHR_GUGU_Foot.L", 0.87, materials, geo, side=1.0))

    structural.append(create_scarf_wrap(materials["red"], materials["red_shadow"], accessories))
    structural.append(add_ellipsoid("ACC_GUGU_Scarf_Knot", (1.83, 0.72, 3.38), (0.30, 0.25, 0.38), materials["red"], accessories, rotation=(0.22, -0.28, 0.18), segments=36))
    scarf_tail_a_obj = create_feather_mesh(
        "ACC_GUGU_Scarf_Tail_A",
        [pixel_point(x, y, 0.88) for x, y in [(409, 433), (441, 414), (470, 399)]],
        [0.17, 0.42, 0.035],
        0.050,
        materials["red"],
        accessories,
        thickness_axis=Vector((0, 1, 0)),
    )
    scarf_tail_b_obj = create_feather_mesh(
        "ACC_GUGU_Scarf_Tail_B",
        [pixel_point(x, y, 0.90) for x, y in [(409, 443), (441, 461), (466, 484)]],
        [0.17, 0.40, 0.035],
        0.050,
        materials["red"],
        accessories,
        thickness_axis=Vector((0, 1, 0)),
    )
    scarf_tail_pivot = pixel_point(407, 438, 0.88)
    rotate_around_pivot_preserve_front(scarf_tail_a_obj, scarf_tail_pivot, math.radians(44), front_scale=0.96)
    rotate_around_pivot_preserve_front(scarf_tail_b_obj, scarf_tail_pivot, math.radians(44), front_scale=0.96)
    structural.extend([scarf_tail_a_obj, scarf_tail_b_obj])

    belly_contour = [
        (188, 451), (211, 440), (247, 435), (286, 436), (328, 442), (356, 459),
        (369, 500), (374, 552), (365, 604), (342, 635), (310, 650), (274, 656),
        (238, 648), (211, 626), (195, 592), (187, 548), (184, 497),
    ]
    create_domed_contour_volume(
        "DEC_GUGU_BellyPatch",
        belly_contour,
        -1.55,
        -1.39,
        -1.98,
        materials["cream"],
        decals,
        inner_scales=(0.82, 0.52),
    )

    strap = create_feather_mesh(
        "ACC_GUGU_Satchel_Strap",
        [pixel_point(x, y, depth) for x, y, depth in [(175, 449, -1.49), (205, 471, -1.53), (245, 500, -1.58), (285, 527, -1.62), (325, 555, -1.66), (363, 582, -1.70)]],
        [0.105, 0.105, 0.105, 0.105, 0.105, 0.095],
        0.028,
        materials["gold"],
        accessories,
        thickness_axis=Vector((0, 1, 0)),
    )
    strap.location.y -= 0.34
    structural.append(strap)
    bag_ring = add_torus("ACC_GUGU_Satchel_Ring", tuple(pixel_point(356, 572, -1.98)), 0.155, 0.045, materials["gold"], accessories)
    raw_bag_body = [(348, 544), (398, 546), (421, 571), (420, 629), (400, 657), (360, 662), (335, 641), (330, 581)]
    raw_bag_flap = [(344, 543), (401, 544), (418, 565), (407, 598), (371, 605), (339, 587)]
    bag_body = [(375 + (x - 375) * 0.95, 603 + (y - 603) * 0.90) for x, y in raw_bag_body]
    bag_flap = [(375 + (x - 375) * 0.95, 573 + (y - 573) * 0.90) for x, y in raw_bag_flap]
    bag_body_obj = create_domed_contour_volume(
        "ACC_GUGU_Satchel_Body",
        bag_body,
        -1.68,
        -1.42,
        -1.94,
        materials["gold"],
        accessories,
        inner_scales=(0.80, 0.50),
    )
    bag_flap_obj = create_bezier_contour_volume("ACC_GUGU_Satchel_Flap", bag_flap, -1.95, -1.80, materials["gold"], accessories, bevel=0.045)
    bag_button = add_ellipsoid("ACC_GUGU_Satchel_Button", tuple(pixel_point(403, 580, -1.94)), (0.095, 0.040, 0.11), materials["gold"], decals, segments=28)
    bag_pivot = pixel_point(345, 555, -1.55)
    bag_angle = math.radians(12)
    for obj in (bag_ring, bag_body_obj, bag_flap_obj, bag_button):
        rotate_around_pivot_preserve_front(obj, bag_pivot, bag_angle)
        obj.location.y -= 0.34
    structural.extend([bag_ring, bag_body_obj, bag_flap_obj])

    return structural


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def create_camera(name: str, location: tuple[float, float, float], target: Vector, collection: bpy.types.Collection) -> bpy.types.Object:
    data = bpy.data.cameras.new(name)
    data.type = "ORTHO"
    data.ortho_scale = IMAGE_HEIGHT * PX
    data.lens = 70
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    collection.objects.link(obj)
    point_at(obj, target)
    return obj


def setup_validation_cameras(collection: bpy.types.Collection) -> dict[str, bpy.types.Object]:
    image_center_z = world_z(IMAGE_HEIGHT * 0.5)
    target = Vector((0.0, 0.0, image_center_z))
    distance = 24.0
    return {
        "front": create_camera("CAM_验证_正面", (0.0, -distance, image_center_z), target, collection),
        "side": create_camera("CAM_验证_侧面", (distance, 0.0, image_center_z), target, collection),
        "back": create_camera("CAM_验证_背面", (0.0, distance, image_center_z), target, collection),
        "three_quarter": create_camera("CAM_验证_四分之三", (8.5, -22.0, 4.15), Vector((0.0, 0.0, 3.55)), collection),
    }


def add_area_light(name: str, location: tuple[float, float, float], energy: float, size: float, color: tuple[float, float, float], collection: bpy.types.Collection) -> None:
    data = bpy.data.lights.new(name, "AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    data.color = color
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    collection.objects.link(obj)
    point_at(obj, Vector((0.0, 0.0, 3.6)))


def create_cyclorama(material: bpy.types.Material, collection: bpy.types.Collection) -> bpy.types.Object:
    """创建无明显地平线的棚拍弧形背景。"""
    half_width = 30.0
    profile = [(-26.0, -0.055), (28.0, -0.055), (30.5, 0.45), (32.5, 2.2), (33.5, 5.2), (33.5, 13.0)]
    vertices = [(x, y, z) for y, z in profile for x in (-half_width, half_width)]
    faces = []
    for index in range(len(profile) - 1):
        start = index * 2
        faces.append((start, start + 1, start + 3, start + 2))
    mesh = bpy.data.meshes.new("STAGE_无缝背景_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("STAGE_无缝背景", mesh)
    mesh.materials.append(material)
    collection.objects.link(obj)
    for polygon in mesh.polygons:
        polygon.use_smooth = True
    bevel = obj.modifiers.new("背景圆角", "BEVEL")
    bevel.width = 0.65
    bevel.segments = 8
    return obj


def setup_render(scene: bpy.types.Scene, stage: bpy.types.Collection, ground_material: bpy.types.Material) -> None:
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 540
    scene.render.resolution_y = 887
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100
    world = scene.world or bpy.data.worlds.new("咕咕世界")
    scene.world = world
    world.use_nodes = True
    nodes = world.node_tree.nodes
    nodes.clear()
    lighting_background = nodes.new("ShaderNodeBackground")
    lighting_background.name = "环境照明"
    lighting_background.inputs["Color"].default_value = (0.72, 0.78, 0.86, 1.0)
    lighting_background.inputs["Strength"].default_value = 0.30
    camera_background = nodes.new("ShaderNodeBackground")
    camera_background.name = "相机暖白背景"
    camera_background.inputs["Color"].default_value = (0.97, 0.95, 0.91, 1.0)
    camera_background.inputs["Strength"].default_value = 4.0
    light_path = nodes.new("ShaderNodeLightPath")
    mix_shader = nodes.new("ShaderNodeMixShader")
    output = nodes.new("ShaderNodeOutputWorld")
    links = world.node_tree.links
    links.new(light_path.outputs["Is Camera Ray"], mix_shader.inputs[0])
    links.new(lighting_background.outputs["Background"], mix_shader.inputs[1])
    links.new(camera_background.outputs["Background"], mix_shader.inputs[2])
    links.new(mix_shader.outputs["Shader"], output.inputs["Surface"])
    add_area_light("主光", (-5.5, -7.0, 10.0), 820, 5.5, (1.0, 0.86, 0.75), stage)
    add_area_light("补光", (5.5, -4.0, 6.5), 270, 4.5, (0.62, 0.82, 1.0), stage)
    add_area_light("轮廓光", (2.0, 6.0, 9.0), 390, 4.0, (0.50, 0.72, 1.0), stage)
    ground_shader = ground_material.node_tree.nodes.get("Principled BSDF")
    if ground_shader and "Emission Color" in ground_shader.inputs:
        ground_shader.inputs["Emission Color"].default_value = hex_color(PALETTE["ground"])
        ground_shader.inputs["Emission Strength"].default_value = 3.0
    bpy.ops.mesh.primitive_plane_add(size=100.0, location=(0.0, 0.0, -0.055))
    ground = bpy.context.object
    ground.name = "STAGE_地面"
    ground.data.materials.append(ground_material)
    for current in list(ground.users_collection):
        current.objects.unlink(ground)
    stage.objects.link(ground)


def render_views(scene: bpy.types.Scene, cameras: dict[str, bpy.types.Object], prefix: str) -> None:
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    for role in ("front", "side", "back", "three_quarter"):
        scene.camera = cameras[role]
        scene.render.filepath = str(RENDER_DIR / f"{prefix}-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    stage_name = parse_stage()
    MODEL_DIR.mkdir(parents=True, exist_ok=True)
    RENDER_DIR.mkdir(parents=True, exist_ok=True)
    reset_scene()

    geo = make_collection("CHR_GUGU_GEO")
    face = make_collection("CHR_GUGU_FACE")
    accessories = make_collection("CHR_GUGU_ACCESSORIES")
    decals = make_collection("CHR_GUGU_DECALS")
    validation = make_collection("CHR_GUGU_VALIDATION")
    stage = make_collection("CHR_GUGU_STAGE")
    materials = {
        key: make_material(f"MAT_GUGU_{key}", color, *MATERIAL_PROFILES[key])
        for key, color in PALETTE.items()
    }
    structural_objects = build_primary_forms(materials, geo)
    if stage_name != "primary":
        structural_objects.extend(build_secondary_forms(materials, geo, face, accessories, decals))
    if stage_name == "depth_corrected":
        apply_character_world_depth_scale(0.90)
    elif stage_name == "final_refined":
        apply_character_world_depth_scale(0.87)
    elif stage_name in {"multiview_final", "animation_face_final", "topology_final", "topology_closed", "shading_final", "delivery_final"}:
        apply_character_world_depth_scale(0.87)
        transform_named_meshes_world({"CHR_GUGU_Head"}, y_scale=1.10, y_anchor=1.10)
        transform_named_meshes_world(
            {
                "CHR_GUGU_Eye.R", "CHR_GUGU_Eye.L",
                "CHR_GUGU_Brow.R", "CHR_GUGU_Brow.L",
                "CHR_GUGU_CheekPad.R", "CHR_GUGU_CheekPad.L",
                "CHR_GUGU_Beak_Upper", "CHR_GUGU_Beak_Lower",
                "DEC_GUGU_BeakNostril.LR",
            },
            y_offset=-0.38,
        )
        transform_named_meshes_world({"CHR_GUGU_Torso"}, y_scale=0.87, y_anchor=-1.45)
        transform_named_meshes_world(
            {"ACC_GUGU_Satchel_Ring", "ACC_GUGU_Satchel_Body", "ACC_GUGU_Satchel_Flap", "ACC_GUGU_Satchel_Button"},
            y_offset=0.28,
        )
        transform_named_meshes_world({"ACC_GUGU_Scarf_Knot"}, y_offset=0.15)
        transform_named_meshes_world({"ACC_GUGU_Scarf_Tail_A", "ACC_GUGU_Scarf_Tail_B"}, y_offset=0.52)
        transform_named_meshes_world(
            {"CHR_GUGU_Tail", "DEC_GUGU_TailCover"},
            y_scale=0.82,
            y_anchor=0.90,
            z_offset=0.20,
        )
        if stage_name == "delivery_final":
            transform_named_meshes_world(
                {
                    "CHR_GUGU_Wing.R", "DEC_GUGU_WingLayer.R.1", "DEC_GUGU_WingLayer.R.2",
                    "DEC_GUGU_WingFeatherDetail.R",
                },
                x_offset=-13.0 * PX,
            )
            transform_named_meshes_world(
                {
                    "CHR_GUGU_Wing.L", "DEC_GUGU_WingLayer.L.1", "DEC_GUGU_WingLayer.L.2",
                    "DEC_GUGU_WingFeatherDetail.L",
                },
                x_offset=7.0 * PX,
            )
    cameras = setup_validation_cameras(validation)
    setup_render(bpy.context.scene, stage, materials["ground"])

    expected_names = {
        "CHR_GUGU_Head", "CHR_GUGU_Torso",
        "CHR_GUGU_Crest_A", "CHR_GUGU_Crest_B", "CHR_GUGU_Crest_C",
        "CHR_GUGU_Eye.R", "CHR_GUGU_Eye.L",
        "CHR_GUGU_Brow.R", "CHR_GUGU_Brow.L",
        "CHR_GUGU_CheekPad.R", "CHR_GUGU_CheekPad.L",
        "CHR_GUGU_Beak_Upper", "CHR_GUGU_Beak_Lower",
        "CHR_GUGU_Wing.R", "CHR_GUGU_Wing.L", "CHR_GUGU_Tail",
        "CHR_GUGU_Leg.R", "CHR_GUGU_Leg.L", "CHR_GUGU_Foot.R", "CHR_GUGU_Foot.L",
        "ACC_GUGU_Scarf_Wrap", "ACC_GUGU_Scarf_Knot",
        "ACC_GUGU_Scarf_Tail_A", "ACC_GUGU_Scarf_Tail_B",
        "ACC_GUGU_Satchel_Strap", "ACC_GUGU_Satchel_Ring",
        "ACC_GUGU_Satchel_Body", "ACC_GUGU_Satchel_Flap",
    }
    actual_names = {obj.name for obj in structural_objects}
    if stage_name != "primary" and actual_names != expected_names:
        raise RuntimeError(
            "结构部件门禁失败："
            + json.dumps(
                {
                    "expected": len(expected_names),
                    "actual": len(actual_names),
                    "missing": sorted(expected_names - actual_names),
                    "extra": sorted(actual_names - expected_names),
                },
                ensure_ascii=False,
            )
        )

    bpy.context.scene["gugu_schema"] = "gugu_character.v3"
    bpy.context.scene["gugu_stage"] = stage_name
    bpy.context.scene["expected_structural_parts"] = 28
    bpy.context.scene["current_structural_parts"] = len(structural_objects)
    bpy.context.scene["reference_manifest"] = str(ROOT / "Assets/Brand/Model/analysis/reference/reference_manifest.json")

    if stage_name == "primary":
        output_blend = PRIMARY_BLEND
        render_prefix = "gugu-v3-stage10"
    elif stage_name == "complete_blockout":
        output_blend = COMPLETE_BLOCKOUT_BLEND
        render_prefix = "gugu-v3-stage20"
    elif stage_name == "secondary_refined":
        output_blend = SECONDARY_REFINED_BLEND
        render_prefix = "gugu-v3-stage30"
    elif stage_name == "form_refined":
        output_blend = FORM_REFINED_BLEND
        render_prefix = "gugu-v3-stage40"
    elif stage_name == "detail_refined":
        output_blend = DETAIL_REFINED_BLEND
        render_prefix = "gugu-v3-stage50"
    elif stage_name == "static_candidate":
        output_blend = STATIC_FINAL_BLEND
        render_prefix = "gugu-v3-stage60"
    elif stage_name == "lookdev_final":
        output_blend = LOOKDEV_FINAL_BLEND
        render_prefix = "gugu-v3-stage70"
    elif stage_name == "polished_form":
        output_blend = POLISHED_FORM_BLEND
        render_prefix = "gugu-v3-stage80"
    elif stage_name == "production_candidate":
        output_blend = PRODUCTION_CANDIDATE_BLEND
        render_prefix = "gugu-v3-stage90"
    elif stage_name == "material_refined":
        output_blend = MATERIAL_REFINED_BLEND
        render_prefix = "gugu-v3-stage100"
    elif stage_name == "depth_refined":
        output_blend = DEPTH_REFINED_BLEND
        render_prefix = "gugu-v3-stage110"
    elif stage_name == "surface_refined":
        output_blend = SURFACE_REFINED_BLEND
        render_prefix = "gugu-v3-stage120"
    elif stage_name == "detail_volume":
        output_blend = DETAIL_VOLUME_BLEND
        render_prefix = "gugu-v3-stage130"
    elif stage_name == "hero_form":
        output_blend = HERO_FORM_BLEND
        render_prefix = "gugu-v3-stage140"
    elif stage_name == "static_qa":
        output_blend = STATIC_QA_BLEND
        render_prefix = "gugu-v3-stage150"
    elif stage_name == "depth_corrected":
        output_blend = DEPTH_CORRECTED_BLEND
        render_prefix = "gugu-v3-stage160"
    elif stage_name == "final_refined":
        output_blend = FINAL_REFINED_BLEND
        render_prefix = "gugu-v3-stage170"
    elif stage_name == "multiview_final":
        output_blend = MULTIVIEW_FINAL_BLEND
        render_prefix = "gugu-v3-stage180"
    elif stage_name == "animation_face_final":
        output_blend = ANIMATION_FACE_BLEND
        render_prefix = "gugu-v3-stage190"
    elif stage_name == "topology_final":
        output_blend = TOPOLOGY_FINAL_BLEND
        render_prefix = "gugu-v3-stage200"
    elif stage_name == "topology_closed":
        output_blend = TOPOLOGY_CLOSED_BLEND
        render_prefix = "gugu-v3-stage210"
    elif stage_name == "shading_final":
        output_blend = SHADING_FINAL_BLEND
        render_prefix = "gugu-v3-stage220"
    else:
        output_blend = DELIVERY_FINAL_BLEND
        render_prefix = "gugu-v3-stage230"
    bpy.ops.wm.save_as_mainfile(filepath=str(output_blend))
    render_views(bpy.context.scene, cameras, render_prefix)
    print(
        "CODEX_GUGU_BUILD="
        + json.dumps(
            {
                "blend": str(output_blend),
                "stage": stage_name,
                "objects": [obj.name for obj in structural_objects],
                "renders": [str(RENDER_DIR / f"{render_prefix}-{role}.png") for role in ("front", "side", "back", "three_quarter")],
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
