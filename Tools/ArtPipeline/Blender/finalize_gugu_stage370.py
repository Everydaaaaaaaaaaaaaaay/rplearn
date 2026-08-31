"""将可见曲线固化为导出网格，生成 stage370 交付源文件。"""

from __future__ import annotations

from pathlib import Path

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[3]
BASELINE_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-360-art-final.blend"
OUTPUT_BLEND = ROOT / "Assets/Brand/Model/source/gugu-v3-stage-370-art-delivery.blend"
RENDER_DIR = ROOT / "Assets/Brand/Model/renders/gugu-v3"


def fill_boundary_loops(bm: bmesh.types.BMesh) -> None:
    """按连通分量分别封闭每一个边界环。"""
    remaining = {edge for edge in bm.edges if len(edge.link_faces) == 1}
    while remaining:
        seed = remaining.pop()
        component = {seed}
        stack = [seed]
        while stack:
            edge = stack.pop()
            for vertex in edge.verts:
                for linked in vertex.link_edges:
                    if linked in remaining:
                        remaining.remove(linked)
                        component.add(linked)
                        stack.append(linked)
        bmesh.ops.edgeloop_fill(bm, edges=list(component), mat_nr=0, use_smooth=True)


def convert_character_curves_to_meshes() -> list[str]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    converted: list[str] = []
    curves = [
        obj for obj in bpy.context.scene.objects
        if obj.type == "CURVE" and obj.name.startswith(("CHR_", "ACC_", "DEC_"))
    ]
    for curve in curves:
        original_name = curve.name
        original_matrix = curve.matrix_world.copy()
        collections = list(curve.users_collection)
        curve.data.use_fill_caps = True
        curve.data.update_tag()
        depsgraph.update()
        evaluated = curve.evaluated_get(depsgraph)
        mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
        mesh.name = f"{original_name}_Mesh"
        bm = bmesh.new()
        bm.from_mesh(mesh)
        fill_boundary_loops(bm)
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        mesh_obj = bpy.data.objects.new(f"{original_name}_固化", mesh)
        for collection in collections:
            collection.objects.link(mesh_obj)
        mesh_obj.matrix_world = original_matrix
        bpy.data.objects.remove(curve, do_unlink=True)
        mesh_obj.name = original_name
        for polygon in mesh.polygons:
            polygon.use_smooth = True
        converted.append(original_name)
    return sorted(converted)


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
        scene.render.filepath = str(RENDER_DIR / f"gugu-v3-stage370-{role}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    if not BASELINE_BLEND.exists():
        raise FileNotFoundError(f"缺少 stage360 基线：{BASELINE_BLEND}")
    bpy.ops.wm.open_mainfile(filepath=str(BASELINE_BLEND))
    converted = convert_character_curves_to_meshes()
    bpy.context.scene["gugu_stage"] = "art_delivery_370"
    bpy.context.scene["art_direction"] = "flat_face_full_body_soft_npr_delivery"
    bpy.context.scene["export_curve_meshes"] = ",".join(converted)
    render_views()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUTPUT_BLEND))
    print(f"stage370 已保存：{OUTPUT_BLEND}；固化曲线：{converted}")


if __name__ == "__main__":
    main()
