"""在空场景重新导入咕咕 GLB，验证开放格式交付完整性。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

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
    parser.add_argument("--glb", required=True)
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    glb = Path(args.glb).resolve()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    manifest_path = glb.with_suffix(".manifest.json")
    if not manifest_path.exists():
        raise FileNotFoundError(f"缺少 GLB 导出清单：{manifest_path}")
    export_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    expected_names = set(export_manifest["mesh_objects"])

    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(glb))

    meshes = sorted([obj for obj in bpy.context.scene.objects if obj.type == "MESH"], key=lambda obj: obj.name)
    names = {obj.name for obj in meshes}
    missing = sorted(EXPECTED_STRUCTURAL - names)
    missing_exported = sorted(expected_names - names)
    unexpected_exported = sorted(names - expected_names)
    empty_materials = sorted(obj.name for obj in meshes if not obj.material_slots or any(slot.material is None for slot in obj.material_slots))
    zero_dimensions = sorted(obj.name for obj in meshes if min(float(value) for value in obj.dimensions) <= 1e-5)
    blockers = []
    if missing:
        blockers.append(f"GLB 缺少结构部件：{missing}")
    if missing_exported:
        blockers.append(f"GLB 缺少导出清单部件：{missing_exported}")
    if unexpected_exported:
        blockers.append(f"GLB 含有清单外部件：{unexpected_exported}")
    if len(meshes) != int(export_manifest["mesh_object_count"]):
        blockers.append(
            "GLB 网格对象数量与导出清单不一致："
            f"{len(meshes)} != {export_manifest['mesh_object_count']}"
        )
    if empty_materials:
        blockers.append(f"GLB 存在空材质：{empty_materials}")
    if zero_dimensions:
        blockers.append(f"GLB 存在零厚度对象：{zero_dimensions}")

    report = {
        "schema": "gugu_glb_validation.v1",
        "glb": str(glb),
        "export_manifest": str(manifest_path),
        "file_size_bytes": glb.stat().st_size,
        "mesh_object_count": len(meshes),
        "material_count": len(bpy.data.materials),
        "missing_structural_parts": missing,
        "missing_exported_parts": missing_exported,
        "unexpected_exported_parts": unexpected_exported,
        "empty_material_objects": empty_materials,
        "zero_dimension_objects": zero_dimensions,
        "blockers": blockers,
        "verdict": "PASS" if not blockers else "FAIL",
        "objects": [
            {
                "name": obj.name,
                "vertices": len(obj.data.vertices),
                "polygons": len(obj.data.polygons),
                "materials": [slot.material.name if slot.material else None for slot in obj.material_slots],
            }
            for obj in meshes
        ],
    }
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("CODEX_GUGU_GLB_VALIDATION=" + json.dumps({"out": str(out), "verdict": report["verdict"], "blockers": blockers}, ensure_ascii=False))


if __name__ == "__main__":
    main()
