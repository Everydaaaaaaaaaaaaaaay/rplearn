"""在 Blender 后台对咕咕静态模型执行绑定前网格审计。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy


EXPECTED_STRUCTURAL = {
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


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def mesh_audit(obj: bpy.types.Object) -> dict[str, object]:
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bm.verts.ensure_lookup_table()
    bm.edges.ensure_lookup_table()
    bm.faces.ensure_lookup_table()
    boundary_edges = sum(1 for edge in bm.edges if len(edge.link_faces) == 1)
    non_manifold_edges = sum(1 for edge in bm.edges if len(edge.link_faces) != 2)
    loose_edges = sum(1 for edge in bm.edges if len(edge.link_faces) == 0)
    loose_vertices = sum(1 for vertex in bm.verts if len(vertex.link_edges) == 0)
    degenerate_faces = sum(1 for face in bm.faces if face.calc_area() < 1e-10)
    bm.free()

    dimensions = [float(value) for value in obj.dimensions]
    determinant = float(obj.matrix_world.to_3x3().determinant())
    material_slots = [slot.material.name if slot.material else None for slot in obj.material_slots]
    return {
        "name": obj.name,
        "collection_names": sorted(collection.name for collection in obj.users_collection),
        "vertices": len(mesh.vertices),
        "edges": len(mesh.edges),
        "polygons": len(mesh.polygons),
        "boundary_edges": boundary_edges,
        "non_manifold_edges": non_manifold_edges,
        "loose_edges": loose_edges,
        "loose_vertices": loose_vertices,
        "degenerate_faces": degenerate_faces,
        "dimensions": dimensions,
        "matrix_determinant": determinant,
        "negative_scale": determinant < 0.0,
        "material_slots": material_slots,
        "empty_material_slots": sum(slot is None for slot in material_slots),
        "modifiers": [{"name": modifier.name, "type": modifier.type} for modifier in obj.modifiers],
    }


def main() -> None:
    args = parse_args()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    character_meshes = sorted(
        [
            obj for obj in bpy.context.scene.objects
            if obj.type == "MESH" and obj.name.startswith(("CHR_", "ACC_", "DEC_"))
        ],
        key=lambda obj: obj.name,
    )
    audits = [mesh_audit(obj) for obj in character_meshes]
    structural_names = {
        obj.name for obj in character_meshes
        if obj.name.startswith(("CHR_GUGU_", "ACC_GUGU_")) and obj.name in EXPECTED_STRUCTURAL
    }
    missing = sorted(EXPECTED_STRUCTURAL - structural_names)
    extra_structural = sorted(
        obj.name for obj in character_meshes
        if obj.name.startswith(("CHR_GUGU_", "ACC_GUGU_"))
        and obj.name not in EXPECTED_STRUCTURAL
        and not obj.name.startswith("ACC_GUGU_Satchel_Button")
    )

    blockers: list[str] = []
    if missing:
        blockers.append(f"缺少结构部件：{missing}")
    if len(structural_names) != 28:
        blockers.append(f"结构部件数量不是 28：{len(structural_names)}")
    if any(item["non_manifold_edges"] for item in audits):
        blockers.append("存在非流形或开口边")
    if any(item["loose_vertices"] or item["loose_edges"] for item in audits):
        blockers.append("存在松散点或松散边")
    if any(item["degenerate_faces"] for item in audits):
        blockers.append("存在退化面")
    if any(item["negative_scale"] for item in audits):
        blockers.append("存在负缩放/镜像矩阵")
    if any(item["empty_material_slots"] for item in audits):
        blockers.append("存在空材质槽")
    if any(min(item["dimensions"]) <= 1e-5 for item in audits):
        blockers.append("存在零厚度网格")

    report = {
        "schema": "gugu_model_audit.v1",
        "blend": bpy.data.filepath,
        "scene_stage": bpy.context.scene.get("gugu_stage"),
        "expected_structural_parts": 28,
        "actual_structural_parts": len(structural_names),
        "missing_structural_parts": missing,
        "extra_structural_parts": extra_structural,
        "character_mesh_count": len(character_meshes),
        "material_count": len([material for material in bpy.data.materials if material.name.startswith("MAT_GUGU_")]),
        "has_armature": any(obj.type == "ARMATURE" for obj in bpy.context.scene.objects),
        "blockers": blockers,
        "verdict": "PASS" if not blockers else "FAIL",
        "objects": audits,
    }
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("CODEX_GUGU_AUDIT=" + json.dumps({"out": str(out), "verdict": report["verdict"], "blockers": blockers}, ensure_ascii=False))


if __name__ == "__main__":
    main()
