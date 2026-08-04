"""修正 stage410 眨眼与庆祝翅膀，生成 stage420 动画候选。"""

from __future__ import annotations

import importlib.util
import math
from pathlib import Path

import bpy


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-410-rigged-animation.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-420-animation-refined.blend"
PREVIEW_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3/stage420-animation"
STAGE410_SCRIPT = ROOT / "scripts/blender/rig_gugu_stage410.py"


def load_stage410_module():
    spec = importlib.util.spec_from_file_location("gugu_stage410", STAGE410_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"无法加载 stage410 脚本：{STAGE410_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def activate_object(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def add_eyelid_bones(rig: bpy.types.Object) -> None:
    rig.animation_data.action = None
    bpy.context.scene.frame_set(1)
    activate_object(rig)
    bpy.ops.object.mode_set(mode="EDIT")
    armature = rig.data

    # 眼球缩放枢轴改到眼睛中心，闭合时不再坠到脸颊位置。
    for name, center_z in (("eye.R", 4.695), ("eye.L", 4.695)):
        bone = armature.edit_bones[name]
        bone.head.z = center_z
        bone.tail.z = center_z + 0.36

    for name, x in (("eyelid.R", -0.65), ("eyelid.L", 1.08)):
        if name in armature.edit_bones:
            continue
        bone = armature.edit_bones.new(name)
        bone.head = (x, -1.20, 4.695)
        bone.tail = (x, -1.20, 5.02)
        bone.parent = armature.edit_bones["head"]
        bone.use_connect = False
        bone.use_deform = True

    bpy.ops.object.mode_set(mode="POSE")
    for name in ("eyelid.R", "eyelid.L"):
        rig.pose.bones[name].rotation_mode = "XYZ"
    bpy.ops.object.mode_set(mode="OBJECT")


def create_closed_eye_mesh(name: str, center_x: float) -> bpy.types.Object:
    if name in bpy.data.objects:
        return bpy.data.objects[name]

    curve = bpy.data.curves.new(f"{name}_Curve", type="CURVE")
    curve.dimensions = "3D"
    curve.resolution_u = 10
    curve.bevel_depth = 0.035
    curve.bevel_resolution = 3
    curve.resolution_u = 16
    curve.use_fill_caps = True
    spline = curve.splines.new(type="BEZIER")
    spline.bezier_points.add(2)
    coordinates = (
        (center_x - 0.36, -1.20, 4.73),
        (center_x, -1.20, 4.655),
        (center_x + 0.36, -1.20, 4.73),
    )
    for point, coordinate in zip(spline.bezier_points, coordinates):
        point.co = coordinate
        point.handle_left_type = "AUTO"
        point.handle_right_type = "AUTO"

    obj = bpy.data.objects.new(name, curve)
    collection = bpy.data.collections.get("CHR_GUGU_DECALS") or bpy.context.scene.collection
    collection.objects.link(obj)
    material = bpy.data.materials["MAT_GUGU_navy"]
    curve.materials.append(material)
    activate_object(obj)
    bpy.ops.object.convert(target="MESH")
    return bpy.context.object


def bind_closed_eye(obj: bpy.types.Object, rig: bpy.types.Object, bone_name: str) -> None:
    obj.vertex_groups.clear()
    group = obj.vertex_groups.new(name=bone_name)
    group.add(range(len(obj.data.vertices)), 1.0, "REPLACE")
    modifier = obj.modifiers.new(name="咕咕眼皮骨骼变形", type="ARMATURE")
    modifier.object = rig
    modifier.use_vertex_groups = True
    world_matrix = obj.matrix_world.copy()
    obj.parent = rig
    obj.matrix_world = world_matrix


def rebuild_actions(rig: bpy.types.Object, stage410) -> dict[str, bpy.types.Action]:
    rig.animation_data.action = None
    for name in stage410.ANIMATION_SPECS:
        old_action = bpy.data.actions.get(name)
        if old_action:
            bpy.data.actions.remove(old_action, do_unlink=True)

    idle = stage410.build_idle_action(rig)
    add_blink_overlay(rig, 37, stage410)
    add_blink_overlay(rig, 83, stage410)
    stage410.set_action_interpolation(idle)

    celebrate = build_celebrate_action(rig, stage410)
    add_blink_overlay(rig, 14, stage410)
    stage410.set_action_interpolation(celebrate)

    talk = stage410.build_talk_action(rig)
    add_blink_overlay(rig, 29, stage410)
    stage410.set_action_interpolation(talk)
    return {
        "GUGU_IDLE_LOOP": idle,
        "GUGU_CELEBRATE": celebrate,
        "GUGU_TALK_LOOP": talk,
    }


def add_blink_overlay(rig: bpy.types.Object, center: int, stage410) -> None:
    # 收缩眼球到中心，同时把藏在头内的深蓝闭眼线推到最前方。
    for eye_name in ("eye.R", "eye.L"):
        stage410.key_transform(rig, eye_name, center - 3, scale=(1.0, 1.0, 1.0))
        stage410.key_transform(rig, eye_name, center - 1, scale=(1.0, 0.28, 1.0))
        stage410.key_transform(rig, eye_name, center, scale=(1.0, 0.018, 1.0))
        stage410.key_transform(rig, eye_name, center + 1, scale=(1.0, 0.22, 1.0))
        stage410.key_transform(rig, eye_name, center + 3, scale=(1.0, 1.0, 1.0))
    for lid_name in ("eyelid.R", "eyelid.L"):
        stage410.key_transform(rig, lid_name, center - 3, location=(0.0, 0.0, 0.0))
        stage410.key_transform(rig, lid_name, center - 1, location=(0.0, 0.0, 0.48))
        stage410.key_transform(rig, lid_name, center, location=(0.0, 0.0, 0.64))
        stage410.key_transform(rig, lid_name, center + 1, location=(0.0, 0.0, 0.52))
        stage410.key_transform(rig, lid_name, center + 3, location=(0.0, 0.0, 0.0))


def build_celebrate_action(rig: bpy.types.Object, stage410) -> bpy.types.Action:
    action = stage410.create_action(rig, "GUGU_CELEBRATE", 1, 73)
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
        stage410.key_transform(rig, "body", frame, location=location, scale=scale)
    for frame, angle in ((1, 0.0), (13, -4.0), (25, 7.0), (37, -3.0), (49, 2.0), (73, 0.0)):
        stage410.key_transform(rig, "head", frame, rotation=(0.0, math.radians(angle), 0.0))

    # 局部 Z 轴对应世界 -Y；左右符号需要镜像，才能向身体外侧抬翼。
    wing_keys = (
        (1, 0.0, 0.0), (13, -6.0, 0.0), (25, 92.0, -0.80),
        (31, 78.0, -0.72), (37, 98.0, -0.80), (49, 35.0, -0.45),
        (61, -3.0, -0.10), (73, 0.0, 0.0),
    )
    for frame, angle, depth in wing_keys:
        stage410.key_transform(
            rig,
            "wing.R",
            frame,
            location=(0.0, 0.0, depth),
            rotation=(0.0, 0.0, math.radians(-angle)),
        )
        stage410.key_transform(
            rig,
            "wing.L",
            frame,
            location=(0.0, 0.0, depth),
            rotation=(0.0, 0.0, math.radians(angle)),
        )

    for frame, offset in ((1, 0.0), (13, 0.0), (22, -0.03), (25, -0.13), (31, -0.06), (37, -0.11), (43, 0.0), (73, 0.0)):
        stage410.key_transform(rig, "beak.lower", frame, location=(0.0, offset, 0.0))
    for frame, angle in ((1, 0.0), (13, -6.0), (25, 10.0), (37, -8.0), (49, 4.0), (73, 0.0)):
        stage410.key_transform(rig, "satchel", frame, rotation=(0.0, 0.0, math.radians(angle)))
        stage410.key_transform(rig, "tail", frame, rotation=(0.0, 0.0, math.radians(-angle * 0.7)))
        stage410.key_transform(rig, "scarf.tail.A", frame, rotation=(0.0, 0.0, math.radians(angle * 1.6)))
        stage410.key_transform(rig, "scarf.tail.B", frame, rotation=(0.0, 0.0, math.radians(angle * 1.2)))
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
        scene.render.filepath = str(PREVIEW_DIR / f"gugu-stage420-{label}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage410 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    stage410 = load_stage410_module()
    rig = bpy.data.objects[stage410.RIG_NAME]

    add_eyelid_bones(rig)
    closed_right = create_closed_eye_mesh("DEC_GUGU_ClosedEye.R", -0.65)
    closed_left = create_closed_eye_mesh("DEC_GUGU_ClosedEye.L", 1.08)
    bind_closed_eye(closed_right, rig, "eyelid.R")
    bind_closed_eye(closed_left, rig, "eyelid.L")

    actions = rebuild_actions(rig, stage410)
    rig["rig_schema"] = "gugu_lightweight_rig.v2"
    rig["eyelid_mode"] = "hidden_closed_eye_mesh"
    bpy.context.scene["gugu_stage"] = "animation_refined_420"
    bpy.context.scene["rigged_mesh_count"] = 49

    render_previews(rig, actions)
    rig.animation_data.action = actions["GUGU_IDLE_LOOP"]
    bpy.context.scene.frame_start = 1
    bpy.context.scene.frame_end = 97
    bpy.context.scene.frame_set(1)
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage420 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
