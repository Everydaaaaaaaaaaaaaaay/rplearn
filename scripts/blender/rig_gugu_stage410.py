"""为 stage400 咕咕建立轻量骨架、刚性蒙皮和首批卡通动作。"""

from __future__ import annotations

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-400-art-delivery-final.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-410-rigged-animation.blend"
PREVIEW_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3/stage410-animation"

RIG_NAME = "RIG_GUGU"
ANIMATION_SPECS = {
    "GUGU_IDLE_LOOP": (1, 97),
    "GUGU_CELEBRATE": (1, 73),
    "GUGU_TALK_LOOP": (1, 49),
}


def radians(value: float) -> float:
    return math.radians(value)


def add_vertical_bone(
    armature: bpy.types.Armature,
    name: str,
    pivot: tuple[float, float, float],
    length: float,
    parent: str | None = None,
    deform: bool = True,
) -> None:
    bone = armature.edit_bones.new(name)
    bone.head = pivot
    bone.tail = (pivot[0], pivot[1], pivot[2] + length)
    bone.use_deform = deform
    bone.use_connect = False
    if parent:
        bone.parent = armature.edit_bones[parent]


def create_rig() -> bpy.types.Object:
    armature = bpy.data.armatures.new(RIG_NAME)
    rig = bpy.data.objects.new(RIG_NAME, armature)
    bpy.context.scene.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")

    add_vertical_bone(armature, "root", (0.0, 0.0, 0.0), 0.5, deform=False)
    add_vertical_bone(armature, "body", (0.0, 0.0, 1.15), 1.7, "root")
    add_vertical_bone(armature, "head", (0.18, 0.0, 3.35), 1.5, "body")

    add_vertical_bone(armature, "eye.R", (-0.65, -1.50, 4.42), 0.55, "head")
    add_vertical_bone(armature, "eye.L", (1.08, -1.50, 4.42), 0.55, "head")
    add_vertical_bone(armature, "brow.R", (-0.65, -1.40, 5.40), 0.24, "head")
    add_vertical_bone(armature, "brow.L", (1.09, -1.38, 5.40), 0.24, "head")
    add_vertical_bone(armature, "beak.upper", (0.18, -1.66, 4.18), 0.32, "head")
    add_vertical_bone(armature, "beak.lower", (0.18, -1.60, 3.96), 0.28, "head")

    add_vertical_bone(armature, "wing.R", (-1.18, -1.15, 3.55), 0.65, "body")
    add_vertical_bone(armature, "wing.L", (1.38, -1.15, 3.55), 0.65, "body")
    add_vertical_bone(armature, "tail", (0.18, 1.25, 2.16), 0.55, "body")
    add_vertical_bone(armature, "leg.R", (-0.70, 0.0, 0.40), 0.72, "body")
    add_vertical_bone(armature, "leg.L", (0.86, 0.0, 0.40), 0.72, "body")
    add_vertical_bone(armature, "foot.R", (-0.70, -0.25, 0.10), 0.28, "leg.R")
    add_vertical_bone(armature, "foot.L", (0.86, -0.25, 0.10), 0.28, "leg.L")
    add_vertical_bone(armature, "scarf.tail.A", (1.73, 0.84, 3.42), 0.45, "body")
    add_vertical_bone(armature, "scarf.tail.B", (1.73, 0.84, 3.42), 0.45, "body")
    add_vertical_bone(armature, "satchel", (1.36, -1.48, 2.62), 0.55, "body")

    bpy.ops.object.mode_set(mode="POSE")
    for pose_bone in rig.pose.bones:
        pose_bone.rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")

    armature.display_type = "BBONE"
    rig.show_in_front = True
    rig["rig_schema"] = "gugu_lightweight_rig.v1"
    rig["animation_fps"] = 24
    rig["animation_clips"] = json.dumps(ANIMATION_SPECS, ensure_ascii=False)
    return rig


def bone_for_object(name: str) -> str:
    if name == "CHR_GUGU_Eye.R":
        return "eye.R"
    if name == "CHR_GUGU_Eye.L":
        return "eye.L"
    if name == "CHR_GUGU_Brow.R":
        return "brow.R"
    if name == "CHR_GUGU_Brow.L":
        return "brow.L"
    if name == "CHR_GUGU_Beak_Upper" or name == "DEC_GUGU_BeakNostril.LR":
        return "beak.upper"
    if name == "CHR_GUGU_Beak_Lower":
        return "beak.lower"
    if name.startswith("CHR_GUGU_Wing.") or name.startswith("DEC_GUGU_Wing"):
        return "wing.L" if ".L" in name else "wing.R"
    if name in {"CHR_GUGU_Tail", "DEC_GUGU_TailCover"}:
        return "tail"
    if name == "CHR_GUGU_Leg.R":
        return "leg.R"
    if name == "CHR_GUGU_Leg.L":
        return "leg.L"
    if name == "CHR_GUGU_Foot.R" or name.startswith("DEC_GUGU_ToeGroove.R"):
        return "foot.R"
    if name == "CHR_GUGU_Foot.L" or name.startswith("DEC_GUGU_ToeGroove.L"):
        return "foot.L"
    if name == "ACC_GUGU_Scarf_Tail_A":
        return "scarf.tail.A"
    if name == "ACC_GUGU_Scarf_Tail_B":
        return "scarf.tail.B"
    if name in {
        "ACC_GUGU_Satchel_Body",
        "ACC_GUGU_Satchel_Flap",
        "ACC_GUGU_Satchel_Ring",
        "ACC_GUGU_Satchel_Button",
        "DEC_GUGU_Satchel_Seam",
    }:
        return "satchel"
    if name in {
        "CHR_GUGU_Head",
        "CHR_GUGU_Crest_A",
        "CHR_GUGU_Crest_B",
        "CHR_GUGU_Crest_C",
        "CHR_GUGU_CheekPad.R",
        "CHR_GUGU_CheekPad.L",
    }:
        return "head"
    return "body"


def bind_rigid_parts(rig: bpy.types.Object) -> dict[str, str]:
    mapping: dict[str, str] = {}
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or not obj.name.startswith(("CHR_", "ACC_", "DEC_")):
            continue
        bone_name = bone_for_object(obj.name)
        mapping[obj.name] = bone_name
        obj.vertex_groups.clear()
        group = obj.vertex_groups.new(name=bone_name)
        group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
        for modifier in list(obj.modifiers):
            if modifier.type == "ARMATURE":
                obj.modifiers.remove(modifier)
        modifier = obj.modifiers.new(name="咕咕骨骼变形", type="ARMATURE")
        modifier.object = rig
        modifier.use_vertex_groups = True
        world_matrix = obj.matrix_world.copy()
        obj.parent = rig
        obj.matrix_world = world_matrix
    rig["rigid_binding_map"] = json.dumps(mapping, ensure_ascii=False, sort_keys=True)
    return mapping


def reset_pose(rig: bpy.types.Object) -> None:
    for bone in rig.pose.bones:
        bone.location = (0.0, 0.0, 0.0)
        bone.rotation_euler = (0.0, 0.0, 0.0)
        bone.scale = (1.0, 1.0, 1.0)


def key_transform(
    rig: bpy.types.Object,
    bone_name: str,
    frame: int,
    *,
    location: tuple[float, float, float] | None = None,
    rotation: tuple[float, float, float] | None = None,
    scale: tuple[float, float, float] | None = None,
) -> None:
    bone = rig.pose.bones[bone_name]
    if location is not None:
        bone.location = location
        bone.keyframe_insert("location", frame=frame, group=bone_name)
    if rotation is not None:
        bone.rotation_euler = rotation
        bone.keyframe_insert("rotation_euler", frame=frame, group=bone_name)
    if scale is not None:
        bone.scale = scale
        bone.keyframe_insert("scale", frame=frame, group=bone_name)


def create_action(rig: bpy.types.Object, name: str, start: int, end: int) -> bpy.types.Action:
    reset_pose(rig)
    action = bpy.data.actions.new(name=name)
    action.use_fake_user = True
    action.use_frame_range = True
    action.frame_start = start
    action.frame_end = end
    action.use_cyclic = name.endswith("_LOOP")
    rig.animation_data_create()
    rig.animation_data.action = action
    return action


def set_action_interpolation(action: bpy.types.Action) -> None:
    """兼容 Blender 5 分层 Action，将缓动手柄设为自动钳制。"""
    for layer in action.layers:
        for strip in layer.strips:
            channelbags = getattr(strip, "channelbags", ())
            for channelbag in channelbags:
                for fcurve in channelbag.fcurves:
                    for point in fcurve.keyframe_points:
                        point.interpolation = "BEZIER"
                        point.handle_left_type = "AUTO_CLAMPED"
                        point.handle_right_type = "AUTO_CLAMPED"


def add_blink(rig: bpy.types.Object, center: int) -> None:
    for name in ("eye.R", "eye.L"):
        key_transform(rig, name, center - 3, scale=(1.0, 1.0, 1.0))
        key_transform(rig, name, center - 1, scale=(1.0, 0.30, 1.0))
        key_transform(rig, name, center, scale=(1.0, 0.10, 1.0))
        key_transform(rig, name, center + 1, scale=(1.0, 0.24, 1.0))
        key_transform(rig, name, center + 3, scale=(1.0, 1.0, 1.0))


def build_idle_action(rig: bpy.types.Object) -> bpy.types.Action:
    action = create_action(rig, "GUGU_IDLE_LOOP", 1, 97)
    body_keys = {
        1: ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
        25: ((0.0, 0.0, 0.045), (0.988, 1.0, 1.018)),
        49: ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
        73: ((0.0, 0.0, -0.018), (1.006, 1.0, 0.992)),
        97: ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
    }
    for frame, (location, scale) in body_keys.items():
        key_transform(rig, "body", frame, location=location, scale=scale)
    for frame, angle in ((1, -1.4), (25, 1.2), (49, -0.8), (73, 1.0), (97, -1.4)):
        key_transform(rig, "head", frame, rotation=(0.0, radians(angle), 0.0))
    for frame, angle in ((1, 0.0), (25, 2.5), (49, 0.0), (73, -2.0), (97, 0.0)):
        key_transform(rig, "wing.R", frame, rotation=(0.0, 0.0, radians(-angle)))
        key_transform(rig, "wing.L", frame, rotation=(0.0, 0.0, radians(angle)))
    for frame, angle in ((1, -2.0), (25, 3.0), (49, -2.0), (73, 2.0), (97, -2.0)):
        key_transform(rig, "tail", frame, rotation=(0.0, 0.0, radians(angle)))
    for frame, angle in ((1, 1.0), (25, -2.0), (49, 1.0), (73, -1.5), (97, 1.0)):
        key_transform(rig, "satchel", frame, rotation=(0.0, 0.0, radians(angle)))
        key_transform(rig, "scarf.tail.A", frame, rotation=(0.0, 0.0, radians(angle * 1.4)))
        key_transform(rig, "scarf.tail.B", frame, rotation=(0.0, 0.0, radians(-angle * 1.1)))
    add_blink(rig, 37)
    add_blink(rig, 83)
    set_action_interpolation(action)
    return action


def build_celebrate_action(rig: bpy.types.Object) -> bpy.types.Action:
    action = create_action(rig, "GUGU_CELEBRATE", 1, 73)
    body_keys = {
        1: ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
        13: ((0.0, 0.0, -0.13), (1.055, 1.0, 0.91)),
        25: ((0.0, 0.0, 0.46), (0.94, 1.0, 1.08)),
        37: ((0.0, 0.0, -0.08), (1.045, 1.0, 0.94)),
        49: ((0.0, 0.0, 0.055), (0.98, 1.0, 1.025)),
        61: ((0.0, 0.0, -0.018), (1.01, 1.0, 0.99)),
        73: ((0.0, 0.0, 0.0), (1.0, 1.0, 1.0)),
    }
    for frame, (location, scale) in body_keys.items():
        key_transform(rig, "body", frame, location=location, scale=scale)
    for frame, angle in ((1, 0.0), (13, -4.0), (25, 7.0), (37, -3.0), (49, 2.0), (73, 0.0)):
        key_transform(rig, "head", frame, rotation=(0.0, radians(angle), 0.0))
    wing_keys = ((1, 0.0), (13, -8.0), (25, 54.0), (31, 42.0), (37, 58.0), (49, 16.0), (61, -4.0), (73, 0.0))
    for frame, angle in wing_keys:
        key_transform(rig, "wing.R", frame, rotation=(0.0, 0.0, radians(angle)))
        key_transform(rig, "wing.L", frame, rotation=(0.0, 0.0, radians(-angle)))
    for frame, offset in ((1, 0.0), (13, 0.0), (22, -0.03), (25, -0.12), (31, -0.06), (37, -0.10), (43, 0.0), (73, 0.0)):
        key_transform(rig, "beak.lower", frame, location=(0.0, offset, 0.0))
    for frame, angle in ((1, 0.0), (13, -6.0), (25, 10.0), (37, -8.0), (49, 4.0), (73, 0.0)):
        key_transform(rig, "satchel", frame, rotation=(0.0, 0.0, radians(angle)))
        key_transform(rig, "tail", frame, rotation=(0.0, 0.0, radians(-angle * 0.7)))
        key_transform(rig, "scarf.tail.A", frame, rotation=(0.0, 0.0, radians(angle * 1.6)))
        key_transform(rig, "scarf.tail.B", frame, rotation=(0.0, 0.0, radians(angle * 1.2)))
    add_blink(rig, 14)
    set_action_interpolation(action)
    return action


def build_talk_action(rig: bpy.types.Object) -> bpy.types.Action:
    action = create_action(rig, "GUGU_TALK_LOOP", 1, 49)
    for frame, height in ((1, 0.0), (13, 0.025), (25, 0.0), (37, 0.018), (49, 0.0)):
        key_transform(rig, "body", frame, location=(0.0, 0.0, height))
    for frame, angle in ((1, -1.0), (13, 1.2), (25, -1.4), (37, 1.0), (49, -1.0)):
        key_transform(rig, "head", frame, rotation=(0.0, radians(angle), 0.0))
    mouth_keys = (
        (1, 0.0), (5, -0.08), (9, -0.018), (13, -0.11), (17, 0.0),
        (22, -0.07), (26, -0.02), (31, -0.10), (35, 0.0),
        (40, -0.06), (44, -0.015), (49, 0.0),
    )
    for frame, offset in mouth_keys:
        key_transform(rig, "beak.lower", frame, location=(0.0, offset, 0.0))
    for frame, angle in ((1, 0.0), (13, 1.8), (25, -1.3), (37, 1.5), (49, 0.0)):
        key_transform(rig, "wing.R", frame, rotation=(0.0, 0.0, radians(-angle)))
        key_transform(rig, "wing.L", frame, rotation=(0.0, 0.0, radians(angle)))
    add_blink(rig, 29)
    set_action_interpolation(action)
    return action


def render_previews(rig: bpy.types.Object, actions: dict[str, bpy.types.Action]) -> None:
    scene = bpy.context.scene
    scene.camera = bpy.data.objects["CAM_验证_四分之三"]
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    preview_frames = {
        "idle-breathe": ("GUGU_IDLE_LOOP", 25),
        "idle-blink": ("GUGU_IDLE_LOOP", 37),
        "celebrate-anticipation": ("GUGU_CELEBRATE", 13),
        "celebrate-air": ("GUGU_CELEBRATE", 25),
        "celebrate-land": ("GUGU_CELEBRATE", 37),
        "talk-open": ("GUGU_TALK_LOOP", 13),
    }
    for label, (action_name, frame) in preview_frames.items():
        rig.animation_data.action = actions[action_name]
        scene.frame_set(frame)
        scene.render.filepath = str(PREVIEW_DIR / f"gugu-stage410-{label}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage400 母版：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.render.fps_base = 1.0

    rig = create_rig()
    mapping = bind_rigid_parts(rig)
    actions = {
        "GUGU_IDLE_LOOP": build_idle_action(rig),
        "GUGU_CELEBRATE": build_celebrate_action(rig),
        "GUGU_TALK_LOOP": build_talk_action(rig),
    }
    rig.animation_data.action = actions["GUGU_IDLE_LOOP"]
    scene.frame_start, scene.frame_end = ANIMATION_SPECS["GUGU_IDLE_LOOP"]
    scene["gugu_stage"] = "rigged_animation_410"
    scene["binding_mode"] = "rigid_part_skinning"
    scene["rigged_mesh_count"] = len(mapping)

    render_previews(rig, actions)
    rig.animation_data.action = actions["GUGU_IDLE_LOOP"]
    scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(
        "CODEX_GUGU_RIG="
        + json.dumps(
            {
                "blend": str(OUTPUT_BLEND),
                "bones": len(rig.data.bones),
                "rigged_meshes": len(mapping),
                "actions": {name: [start, end] for name, (start, end) in ANIMATION_SPECS.items()},
                "preview_dir": str(PREVIEW_DIR),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
