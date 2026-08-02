"""从已通过 QA 的 Blender 场景导出开放格式 GLB。"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    return parser.parse_args(argv)


def main() -> None:
    args = parse_args()
    output = Path(args.out).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    bpy.ops.object.select_all(action="DESELECT")
    selected = []
    for obj in bpy.context.scene.objects:
        if obj.type == "MESH" and obj.name.startswith(("CHR_", "ACC_", "DEC_")):
            obj.select_set(True)
            selected.append(obj.name)
    if not selected:
        raise RuntimeError("没有找到可导出的咕咕角色网格")

    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_animations=False,
        export_extras=True,
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        check_existing=False,
    )
    print(
        "CODEX_GUGU_EXPORT="
        + json.dumps(
            {"glb": str(output), "mesh_objects": len(selected), "selected": sorted(selected)},
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
