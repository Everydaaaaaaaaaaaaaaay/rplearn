"""把人工审核的部件草案转换成 seeded_part_masks 可直接执行的清单。"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "Assets/Brand/Model/analysis/reference/agent-part-inventory-draft.json"
OUTPUT = ROOT / "Assets/Brand/Model/analysis/reference/gugu-front-seed-manifest.json"

HSV_HINTS = {
    "blue": ([85, 45, 55], [115, 255, 255]),
    "red": ([0, 80, 55], [10, 255, 255]),
    "gold": ([13, 65, 55], [35, 255, 255]),
    "orange": ([0, 80, 55], [16, 255, 255]),
}


def main() -> None:
    source = json.loads(SOURCE.read_text(encoding="utf-8"))
    manifest = source["front_seed_manifest"]
    normalized_parts = []
    for original in manifest["parts"]:
        part = dict(original)
        if part["name"] == "head_shell":
            part.pop("bbox", None)
            part.pop("seed_point", None)
            part["mode"] = "polygon"
            part["polygon"] = [
                [285, 194], [330, 198], [375, 220], [410, 260],
                [426, 310], [423, 360], [405, 410], [376, 440],
                [285, 448], [190, 440], [160, 410], [145, 360],
                [145, 300], [165, 250], [210, 210], [255, 195]
            ]
        hint = part.pop("hsv_hint", None)
        if hint:
            part["hsv_min"], part["hsv_max"] = HSV_HINTS[hint]
        if part["mode"] == "non_background":
            part.setdefault("threshold", 22)
            part.setdefault("close", True)
        if part["mode"] == "dark_lines":
            part.setdefault("value_max", 150)
            part.setdefault("sat_max", 210)
            if part["name"].startswith("beak_nostril"):
                part["value_max"] = 225
                part["sat_max"] = 255
        if part["mode"] == "bright_on_dark":
            part.setdefault("value_min", 195)
            part.setdefault("sat_min", 0)
        normalized_parts.append(part)

    output = {
        "schema": manifest["schema"],
        "image": manifest["image"],
        "image_size": manifest["image_size"],
        "source_inventory": str(SOURCE),
        "parts": normalized_parts,
    }
    OUTPUT.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")
    print(OUTPUT)


if __name__ == "__main__":
    main()
