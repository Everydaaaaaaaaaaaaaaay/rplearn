"""空场景回读咕咕动画 GLB，验证网格、骨骼、动作和循环接缝。"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--glb", required=True)
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def pose_snapshot(rig: bpy.types.Object, action: bpy.types.Action, frame: float) -> dict[str, tuple[float, ...]]:
    rig.animation_data_create()
    rig.animation_data.action = action
    bpy.context.scene.frame_set(int(round(frame)))
    bpy.context.view_layer.update()
    return {
        bone.name: tuple(value for row in bone.matrix for value in row)
        for bone in rig.pose.bones
    }


def max_pose_delta(
    first: dict[str, tuple[float, ...]],
    last: dict[str, tuple[float, ...]],
) -> float:
    return max(
        abs(a - b)
        for name in first
        for a, b in zip(first[name], last[name])
    )


def main() -> None:
    args = parse_args()
    glb = Path(args.glb).resolve()
    out = Path(args.out).resolve()
    manifest_path = glb.with_suffix(".manifest.json")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    out.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))

    meshes = sorted(
        (
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH"
            and "glTF_not_exported" not in {collection.name for collection in obj.users_collection}
        ),
        key=lambda obj: obj.name,
    )
    importer_helpers = sorted(
        obj.name
        for obj in bpy.context.scene.objects
        if "glTF_not_exported" in {collection.name for collection in obj.users_collection}
    )
    armatures = [obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"]
    names = {obj.name for obj in meshes}
    expected_meshes = set(manifest["mesh_objects"])
    missing_meshes = sorted(expected_meshes - names)
    unexpected_meshes = sorted(names - expected_meshes)
    actions = {action.name: action for action in bpy.data.actions}
    expected_actions = set(manifest["actions"])
    missing_actions = sorted(expected_actions - set(actions))
    unexpected_actions = sorted(set(actions) - expected_actions)
    blockers: list[str] = []

    if len(armatures) != 1:
        blockers.append(f"骨架对象数量不是 1：{len(armatures)}")
    if missing_meshes:
        blockers.append(f"缺少网格：{missing_meshes}")
    if unexpected_meshes:
        blockers.append(f"存在清单外网格：{unexpected_meshes}")
    if missing_actions:
        blockers.append(f"缺少动作：{missing_actions}")
    if unexpected_actions:
        blockers.append(f"存在清单外动作：{unexpected_actions}")

    rig = armatures[0] if armatures else None
    missing_bones: list[str] = []
    unexpected_bones: list[str] = []
    if rig:
        bone_names = {bone.name for bone in rig.data.bones}
        expected_bones = set(manifest["bones"])
        missing_bones = sorted(expected_bones - bone_names)
        unexpected_bones = sorted(bone_names - expected_bones)
        if missing_bones:
            blockers.append(f"缺少骨骼：{missing_bones}")
        if unexpected_bones:
            blockers.append(f"存在清单外骨骼：{unexpected_bones}")

    unskinned_meshes = sorted(
        obj.name
        for obj in meshes
        if not any(modifier.type == "ARMATURE" for modifier in obj.modifiers)
    )
    if unskinned_meshes:
        blockers.append(f"存在未蒙皮网格：{unskinned_meshes}")

    action_report: dict[str, dict[str, float | int | bool]] = {}
    if rig:
        for name, expected in manifest["actions"].items():
            if name not in actions:
                continue
            action = actions[name]
            start, end = action.frame_range
            sample_count = int(round(end - start)) + 1
            first = pose_snapshot(rig, action, start)
            last = pose_snapshot(rig, action, end)
            seam_delta = max_pose_delta(first, last)
            expected_samples = int(expected["sample_count"])
            sample_match = sample_count == expected_samples
            seam_ok = math.isfinite(seam_delta) and seam_delta <= 1e-4
            if not sample_match:
                blockers.append(f"动作 {name} 采样数异常：{sample_count} != {expected_samples}")
            if not seam_ok:
                blockers.append(f"动作 {name} 首尾姿态不一致：{seam_delta}")
            action_report[name] = {
                "frame_start": float(start),
                "frame_end": float(end),
                "sample_count": sample_count,
                "expected_sample_count": expected_samples,
                "sample_count_match": sample_match,
                "max_loop_seam_delta": seam_delta,
                "loop_seam_ok": seam_ok,
            }

    empty_materials = sorted(
        obj.name
        for obj in meshes
        if not obj.material_slots or any(slot.material is None for slot in obj.material_slots)
    )
    if empty_materials:
        blockers.append(f"存在空材质：{empty_materials}")

    report = {
        "schema": "gugu_animated_glb_validation.v1",
        "glb": str(glb),
        "manifest": str(manifest_path),
        "file_size_bytes": glb.stat().st_size,
        "mesh_object_count": len(meshes),
        "armature_object_count": len(armatures),
        "bone_count": len(rig.data.bones) if rig else 0,
        "material_count": len(bpy.data.materials),
        "ignored_importer_helpers": importer_helpers,
        "missing_meshes": missing_meshes,
        "unexpected_meshes": unexpected_meshes,
        "missing_bones": missing_bones,
        "unexpected_bones": unexpected_bones,
        "unskinned_meshes": unskinned_meshes,
        "missing_actions": missing_actions,
        "unexpected_actions": unexpected_actions,
        "actions": action_report,
        "empty_material_objects": empty_materials,
        "blockers": blockers,
        "verdict": "PASS" if not blockers else "FAIL",
    }
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        "CODEX_GUGU_ANIMATED_VALIDATION="
        + json.dumps(
            {"out": str(out), "verdict": report["verdict"], "blockers": blockers},
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
