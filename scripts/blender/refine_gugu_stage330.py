"""将侧向羽片投射贴合翼面，消除跨视图尖片，生成 stage330。"""

from __future__ import annotations

from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path("/Volumes/data/rplearn")
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-320-crossview-clean.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-330-wing-surface-fitted.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def ray_hit(
    bvh: BVHTree,
    wing: bpy.types.Object,
    point: Vector,
    sign: float,
    center_yz: tuple[float, float],
) -> tuple[Vector, int]:
    candidate = point.copy()
    center_y, center_z = center_yz
    for attempt in range(9):
        origin = Vector((4.0 * sign, candidate.y, candidate.z))
        direction = Vector((-sign, 0.0, 0.0))
        inverse = wing.matrix_world.inverted()
        local_origin = inverse @ origin
        local_direction = (inverse.to_3x3() @ direction).normalized()
        location, _normal, _index, _distance = bvh.ray_cast(local_origin, local_direction)
        if location is not None:
            return wing.matrix_world @ location, attempt
        candidate.y = center_y + (candidate.y - center_y) * 0.90
        candidate.z = center_z + (candidate.z - center_z) * 0.90
    raise RuntimeError(f"侧羽投射失败：Y={point.y:.3f}, Z={point.z:.3f}")


def fit_mesh_panel(
    obj: bpy.types.Object,
    wing: bpy.types.Object,
    sign: float,
) -> int:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(wing, depsgraph)
    if bvh is None:
        raise RuntimeError(f"无法建立翼面 BVH：{wing.name}")
    world_points = [obj.matrix_world @ vertex.co for vertex in obj.data.vertices]
    center_y = sum(point.y for point in world_points) / len(world_points)
    center_z = sum(point.z for point in world_points) / len(world_points)
    signed_values = [point.x * sign for point in world_points]
    midpoint = (min(signed_values) + max(signed_values)) * 0.5
    inverse = obj.matrix_world.inverted()
    contracted = 0
    for vertex, world in zip(obj.data.vertices, world_points):
        hit, attempts = ray_hit(bvh, wing, world, sign, (center_y, center_z))
        contracted += int(attempts > 0)
        outward = world.x * sign > midpoint
        offset = 0.024 if outward else 0.010
        hit.x += sign * offset
        vertex.co = inverse @ hit
    obj.data.update()
    return contracted


def fit_curve_groove(
    obj: bpy.types.Object,
    wing: bpy.types.Object,
    sign: float,
) -> int:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(wing, depsgraph)
    if bvh is None:
        raise RuntimeError(f"无法建立翼面 BVH：{wing.name}")
    points = [point for spline in obj.data.splines for point in spline.bezier_points]
    world_points = [obj.matrix_world @ point.co for point in points]
    center_y = sum(point.y for point in world_points) / len(world_points)
    center_z = sum(point.z for point in world_points) / len(world_points)
    inverse = obj.matrix_world.inverted()
    contracted = 0
    for point, world in zip(points, world_points):
        hit, attempts = ray_hit(bvh, wing, world, sign, (center_y, center_z))
        contracted += int(attempts > 0)
        hit.x += sign * 0.031
        point.co = inverse @ hit
    obj.data.update_tag()
    return contracted


def fit_side_feathers() -> None:
    results = {}
    for side, sign in (("L", 1.0), ("R", -1.0)):
        wing = bpy.data.objects[f"CHR_GUGU_Wing.{side}"]
        for index in (1, 2):
            name = f"DEC_GUGU_WingSideLayer.{side}.{index}"
            results[name] = fit_mesh_panel(bpy.data.objects[name], wing, sign)
        groove_name = f"DEC_GUGU_WingSideGroove.{side}"
        results[groove_name] = fit_curve_groove(bpy.data.objects[groove_name], wing, sign)
    print("侧羽曲面投射收缩点数：", results)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage330-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage320 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    fit_side_feathers()
    bpy.context.scene["gugu_stage"] = "wing_surface_fitted_330"
    bpy.context.scene["art_direction"] = "flat_face_full_body_surface_fitted_wings"
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage330 已保存：{OUTPUT_BLEND}")


if __name__ == "__main__":
    main()
