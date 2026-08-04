"""审计咕咕 stage420 源骨架、刚性权重、动作范围与关键帧健康度。"""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy


EXPECTED_ACTIONS = {
    "GUGU_IDLE_LOOP": (1, 97),
    "GUGU_CELEBRATE": (1, 73),
    "GUGU_TALK_LOOP": (1, 49),
}


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--blend", required=True)
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def iter_action_fcurves(action: bpy.types.Action):
    for layer in action.layers:
        for strip in layer.strips:
            for channelbag in getattr(strip, "channelbags", ()):
                yield from channelbag.fcurves


def main() -> None:
    args = parse_args()
    blend = Path(args.blend).resolve()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=str(blend))

    rig = bpy.data.objects.get("RIG_GUGU")
    meshes = sorted(
        (
            obj
            for obj in bpy.context.scene.objects
            if obj.type == "MESH" and obj.name.startswith(("CHR_", "ACC_", "DEC_"))
        ),
        key=lambda obj: obj.name,
    )
    blockers: list[str] = []
    mesh_report: list[dict[str, object]] = []
    bone_names = {bone.name for bone in rig.data.bones} if rig else set()

    if rig is None:
        blockers.append("缺少 RIG_GUGU 骨架")
    elif len(rig.data.bones) != 21:
        blockers.append(f"骨骼数量不是 21：{len(rig.data.bones)}")
    if len(meshes) != 49:
        blockers.append(f"角色网格数量不是 49：{len(meshes)}")

    for obj in meshes:
        armature_modifiers = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE"]
        vertex_group_names = {group.name for group in obj.vertex_groups}
        invalid_weights = 0
        influence_counts: list[int] = []
        for vertex in obj.data.vertices:
            assigned = [group for group in vertex.groups if group.weight > 0.0]
            influence_counts.append(len(assigned))
            if len(assigned) != 1 or any(abs(group.weight - 1.0) > 1e-6 for group in assigned):
                invalid_weights += 1
        orphan_groups = sorted(vertex_group_names - bone_names)
        valid_parent = rig is not None and obj.parent == rig
        valid_modifier = (
            len(armature_modifiers) == 1
            and rig is not None
            and armature_modifiers[0].object == rig
        )
        if not valid_parent:
            blockers.append(f"{obj.name} 未显式父级到骨架")
        if not valid_modifier:
            blockers.append(f"{obj.name} 的 Armature 修改器异常")
        if orphan_groups:
            blockers.append(f"{obj.name} 存在无对应骨骼的顶点组：{orphan_groups}")
        if invalid_weights:
            blockers.append(f"{obj.name} 有 {invalid_weights} 个非刚性权重顶点")
        mesh_report.append(
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "parent_is_rig": valid_parent,
                "armature_modifier_valid": valid_modifier,
                "vertex_groups": sorted(vertex_group_names),
                "orphan_vertex_groups": orphan_groups,
                "invalid_rigid_weight_vertices": invalid_weights,
                "max_vertex_influences": max(influence_counts, default=0),
            }
        )

    action_report: dict[str, dict[str, object]] = {}
    actual_actions = {action.name: action for action in bpy.data.actions}
    missing_actions = sorted(set(EXPECTED_ACTIONS) - set(actual_actions))
    unexpected_actions = sorted(set(actual_actions) - set(EXPECTED_ACTIONS))
    if missing_actions:
        blockers.append(f"缺少动作：{missing_actions}")
    if unexpected_actions:
        blockers.append(f"存在清单外动作：{unexpected_actions}")
    for name, expected_range in EXPECTED_ACTIONS.items():
        action = actual_actions.get(name)
        if action is None:
            continue
        frame_range = (int(round(action.frame_start)), int(round(action.frame_end)))
        fcurves = list(iter_action_fcurves(action))
        keyframes = [point for fcurve in fcurves for point in fcurve.keyframe_points]
        finite = all(
            math.isfinite(value)
            for point in keyframes
            for value in (*point.co, *point.handle_left, *point.handle_right)
        )
        if frame_range != expected_range:
            blockers.append(f"动作 {name} 范围异常：{frame_range} != {expected_range}")
        if not fcurves or not keyframes:
            blockers.append(f"动作 {name} 没有关键帧曲线")
        if not finite:
            blockers.append(f"动作 {name} 存在非有限关键帧值")
        action_report[name] = {
            "frame_start": frame_range[0],
            "frame_end": frame_range[1],
            "sample_count": frame_range[1] - frame_range[0] + 1,
            "fcurve_count": len(fcurves),
            "keyframe_count": len(keyframes),
            "finite_keyframes": finite,
            "cyclic": action.use_cyclic,
        }

    report = {
        "schema": "gugu_rig_audit.v1",
        "blend": str(blend),
        "rig_name": rig.name if rig else None,
        "rig_schema": rig.get("rig_schema") if rig else None,
        "bone_count": len(rig.data.bones) if rig else 0,
        "mesh_count": len(meshes),
        "fps": bpy.context.scene.render.fps,
        "missing_actions": missing_actions,
        "unexpected_actions": unexpected_actions,
        "actions": action_report,
        "meshes": mesh_report,
        "blockers": blockers,
        "verdict": "PASS" if not blockers else "FAIL",
    }
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(
        "CODEX_GUGU_RIG_AUDIT="
        + json.dumps(
            {"out": str(out), "verdict": report["verdict"], "blockers": blockers},
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
