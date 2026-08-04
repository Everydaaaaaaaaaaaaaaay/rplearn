"""导出咕咕 stage420 骨骼、蒙皮与多动作 GLB。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy


EXPECTED_ACTIONS = ("GUGU_IDLE_LOOP", "GUGU_CELEBRATE", "GUGU_TALK_LOOP")


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    blend = Path(args.blend).resolve()
    output = Path(args.out).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(blend))

    rig = bpy.data.objects["RIG_GUGU"]
    mesh_objects = sorted(
        obj.name
        for obj in bpy.context.scene.objects
        if obj.type == "MESH" and obj.name.startswith(("CHR_", "ACC_", "DEC_"))
    )
    missing_actions = [name for name in EXPECTED_ACTIONS if name not in bpy.data.actions]
    if missing_actions:
        raise RuntimeError(f"缺少待导出动作：{missing_actions}")

    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True)
    for name in mesh_objects:
        bpy.data.objects[name].select_set(True)
    bpy.context.view_layer.objects.active = rig

    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_frame_range=False,
        export_frame_step=1,
        export_force_sampling=True,
        export_anim_slide_to_zero=True,
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_armature=True,
        export_skins=True,
        export_def_bones=False,
        export_all_influences=False,
        export_extras=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        check_existing=False,
    )

    actions = {
        name: {
            "source_frame_start": int(round(bpy.data.actions[name].frame_start)),
            "source_frame_end": int(round(bpy.data.actions[name].frame_end)),
            "sample_count": int(round(bpy.data.actions[name].frame_end - bpy.data.actions[name].frame_start)) + 1,
        }
        for name in EXPECTED_ACTIONS
    }
    manifest = {
        "schema": "gugu_animated_glb_manifest.v1",
        "source_blend": str(blend),
        "glb": str(output),
        "fps": bpy.context.scene.render.fps,
        "mesh_object_count": len(mesh_objects),
        "mesh_objects": mesh_objects,
        "armature_object": rig.name,
        "bone_count": len(rig.data.bones),
        "bones": sorted(bone.name for bone in rig.data.bones),
        "actions": actions,
    }
    manifest_path = output.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        "CODEX_GUGU_ANIMATED_EXPORT="
        + json.dumps(
            {
                "glb": str(output),
                "manifest": str(manifest_path),
                "meshes": len(mesh_objects),
                "bones": len(rig.data.bones),
                "actions": actions,
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
