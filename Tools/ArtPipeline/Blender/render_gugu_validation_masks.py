"""从现有咕咕场景输出固定配准相机的白底轮廓验证图。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy


GROUPS = {
    "head": ["CHR_GUGU_Head"],
    "torso": ["CHR_GUGU_Torso"],
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", required=True)
    parser.add_argument("--prefix", default="gugu")
    return parser.parse_args(argv)


def make_override_material() -> bpy.types.Material:
    material = bpy.data.materials.new("VAL_白色轮廓")
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    emission = nodes.new("ShaderNodeEmission")
    emission.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)
    emission.inputs["Strength"].default_value = 1.0
    material.node_tree.links.new(emission.outputs["Emission"], output.inputs["Surface"])
    return material


def render_group(scene: bpy.types.Scene, out_dir: Path, prefix: str, group_name: str, names: list[str]) -> list[str]:
    mesh_objects = [obj for obj in scene.objects if obj.type == "MESH"]
    original = {obj.name: obj.hide_render for obj in mesh_objects}
    allowed = set(names)
    for obj in mesh_objects:
        obj.hide_render = obj.name not in allowed

    paths = []
    for role, camera_name in (("front", "CAM_验证_正面"), ("side", "CAM_验证_侧面"), ("back", "CAM_验证_背面")):
        camera = bpy.data.objects.get(camera_name)
        if camera is None:
            continue
        scene.camera = camera
        path = out_dir / f"{prefix}-{group_name}-{role}.png"
        scene.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        paths.append(str(path))

    for obj in mesh_objects:
        obj.hide_render = original[obj.name]
    return paths


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 540
    scene.render.resolution_y = 887
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("VAL_黑色世界")
    scene.world = world
    world.use_nodes = True
    world.node_tree.nodes.clear()
    background = world.node_tree.nodes.new("ShaderNodeBackground")
    output = world.node_tree.nodes.new("ShaderNodeOutputWorld")
    world.node_tree.links.new(background.outputs["Background"], output.inputs["Surface"])
    background.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    background.inputs["Strength"].default_value = 0.0
    scene.view_layers[0].material_override = make_override_material()

    rendered = {}
    rendered["full"] = render_group(
        scene,
        out_dir,
        args.prefix,
        "full",
        [obj.name for obj in scene.objects if obj.type == "MESH" and obj.name.startswith(("CHR_", "ACC_", "DEC_"))],
    )
    for group_name, names in GROUPS.items():
        rendered[group_name] = render_group(scene, out_dir, args.prefix, group_name, names)
    manifest = out_dir / f"{args.prefix}-validation-render-manifest.json"
    manifest.write_text(json.dumps(rendered, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"CODEX_VALIDATION_MANIFEST={manifest}")


if __name__ == "__main__":
    main()
