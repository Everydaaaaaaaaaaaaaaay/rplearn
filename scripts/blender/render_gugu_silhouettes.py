"""在 Blender 后台渲染已配准的正交轮廓图。

运行示例：
blender -b model.blend --python render_gugu_silhouettes.py -- \
  --registration registration.json --out-dir renders
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy
from mathutils import Vector


VIEW_DIRECTIONS = {
    # Blender 正视图：相机从 -Y 看向 +Y。
    "front": Vector((0.0, 1.0, 0.0)),
    # 从 +X 看向 -X，使角色朝向 -Y 时在画面中朝左。
    "side": Vector((-1.0, 0.0, 0.0)),
    "back": Vector((0.0, -1.0, 0.0)),
}
UP = Vector((0.0, 0.0, 1.0))


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--registration", required=True)
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--prefix", default="silhouette")
    parser.add_argument("--views", nargs="+", default=["front", "side", "back"])
    return parser.parse_args(argv)


def evaluated_world_points(objects: list[bpy.types.Object]) -> list[Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    points: list[Vector] = []
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner) for corner in evaluated.bound_box)
    return points


def setup_silhouette_render(scene: bpy.types.Scene) -> None:
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.render.film_transparent = False
    scene.render.resolution_percentage = 100

    world = scene.world or bpy.data.worlds.new("Codex_轮廓世界")
    scene.world = world
    world.use_nodes = True
    world_nodes = world.node_tree.nodes
    world_links = world.node_tree.links
    world_nodes.clear()
    background = world_nodes.new("ShaderNodeBackground")
    output = world_nodes.new("ShaderNodeOutputWorld")
    world_links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    background.inputs["Strength"].default_value = 0.0

    material = bpy.data.materials.get("Codex_白色轮廓") or bpy.data.materials.new("Codex_白色轮廓")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    emission.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    scene.view_layers[0].material_override = material


def ensure_camera(scene: bpy.types.Scene) -> bpy.types.Object:
    data = bpy.data.cameras.get("Codex_轮廓相机") or bpy.data.cameras.new("Codex_轮廓相机")
    camera = bpy.data.objects.get("Codex_轮廓相机")
    if camera is None:
        camera = bpy.data.objects.new("Codex_轮廓相机", data)
        scene.collection.objects.link(camera)
    camera.data.type = "ORTHO"
    scene.camera = camera
    return camera


def render_view(
    scene: bpy.types.Scene,
    camera: bpy.types.Object,
    points: list[Vector],
    registration: dict,
    role: str,
    output: Path,
) -> dict:
    forward = VIEW_DIRECTIONS[role].normalized()
    right = forward.cross(UP).normalized()

    horizontal = [p.dot(right) for p in points]
    vertical = [p.dot(UP) for p in points]
    depth = [p.dot(forward) for p in points]
    object_width = max(horizontal) - min(horizontal)
    object_height = max(vertical) - min(vertical)
    object_h_center = (max(horizontal) + min(horizontal)) * 0.5
    object_v_center = (max(vertical) + min(vertical)) * 0.5
    depth_center = (max(depth) + min(depth)) * 0.5

    image_width, image_height = registration["image_size"]
    bbox_x, bbox_y, bbox_width, bbox_height = registration["bbox"]
    target_x = bbox_x + bbox_width * 0.5
    target_y = bbox_y + bbox_height * 0.5
    target_height_ratio = bbox_height / image_height

    camera.data.ortho_scale = object_height / max(target_height_ratio, 1e-6)
    horizontal_span = camera.data.ortho_scale * image_width / image_height
    camera_h_center = object_h_center - (target_x / image_width - 0.5) * horizontal_span
    camera_v_center = object_v_center - (0.5 - target_y / image_height) * camera.data.ortho_scale

    target = right * camera_h_center + UP * camera_v_center + forward * depth_center
    distance = max(object_width, object_height, max(depth) - min(depth)) * 4.0 + 10.0
    camera.location = target - forward * distance
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.clip_start = 0.01
    camera.data.clip_end = distance * 3.0

    scene.render.resolution_x = int(image_width)
    scene.render.resolution_y = int(image_height)
    scene.render.filepath = str(output)
    bpy.ops.render.render(write_still=True)

    return {
        "role": role,
        "path": str(output),
        "image_size": [image_width, image_height],
        "object_screen_bounds": {
            "width": object_width,
            "height": object_height,
        },
        "ortho_scale": camera.data.ortho_scale,
    }


def main() -> None:
    args = parse_args()
    registration_data = json.loads(Path(args.registration).read_text(encoding="utf-8"))
    registrations = {item["role"]: item for item in registration_data["views"]}
    # 只测角色资产，排除地面、软投影、参考平面等舞台辅助网格。
    meshes = [
        obj for obj in bpy.context.scene.objects
        if obj.type == "MESH"
        and not obj.hide_render
        and obj.name.startswith(("CHR_", "ACC_", "DEC_"))
    ]
    if not meshes:
        raise RuntimeError("场景中没有可渲染网格")

    points = evaluated_world_points(meshes)
    scene = bpy.context.scene
    setup_silhouette_render(scene)
    camera = ensure_camera(scene)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    rendered = []
    for role in args.views:
        if role not in VIEW_DIRECTIONS or role not in registrations:
            continue
        output = out_dir / f"{args.prefix}-{role}.png"
        rendered.append(render_view(scene, camera, points, registrations[role], role, output))

    manifest = {
        "schema": "gugu_silhouette_render.v1",
        "blend": bpy.data.filepath,
        "mesh_objects": [obj.name for obj in meshes],
        "views": rendered,
    }
    manifest_path = out_dir / f"{args.prefix}-render-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CODEX_RENDER_MANIFEST={manifest_path}")


if __name__ == "__main__":
    main()
