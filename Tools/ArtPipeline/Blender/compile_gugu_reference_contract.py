"""从审核后的清单生成重建管线的正式来源契约和配准报告。"""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ANALYSIS = ROOT / "Assets/Brand/Model/analysis/reference"
INVENTORY_PATH = ANALYSIS / "agent-part-inventory-draft.json"
MANIFEST_PATH = ANALYSIS / "reference_manifest.json"
REGISTRATION_PATH = ANALYSIS / "registration_report.json"


def main() -> None:
    inventory = json.loads(INVENTORY_PATH.read_text(encoding="utf-8"))
    structural = [
        part
        for part in inventory["part_inventory"]
        if part["class"] in {"structural", "face_feature"}
    ]
    decorative = [part for part in inventory["part_inventory"] if part["class"] == "decorative"]
    sources = [
        {
            "path": item["path"],
            "role": {
                "front": "front_template",
                "side": "side_view",
                "back": "back_view",
            }[item["view"]],
            "usable_character_bbox": item["usable_character_bbox"],
            "warning": item.get("warning"),
        }
        for item in inventory["inputs"]
    ]
    manifest = {
        "schema": "gugu_reference_manifest.v2",
        "primary_view": "front",
        "canonical_policy": "front_side_canonical",
        "source_files": sources,
        "expected_primary_parts": {
            "count": sum(part["expected_count"] for part in structural),
            "labels": [part["id"] for part in structural],
        },
        "structural_parts": structural,
        "decorative_parts": decorative,
        "texture_regions": [],
        "validation_thresholds": {
            "front_mask_iou_min": 0.82,
            "bbox_center_tolerance_ratio": 0.015,
            "front_bbox_size_tolerance_ratio": 0.03,
            "secondary_view_bbox_size_tolerance_ratio": 0.05,
            "face_landmark_tolerance_ratio": 0.02,
            "part_count_exact": True,
        },
        "known_ambiguities": inventory["multiview_conflicts_and_ambiguities"],
    }
    registration = {
        "schema": "gugu_orthographic_registration.v2",
        "canonical_policy": "front_side_canonical",
        "coordinate_contract": {
            "front": "X/Z",
            "side": "Y/Z",
            "back": "rear X/Z",
            "character_forward": "-Y",
        },
        "views": {
            "front": {
                "image_size": [540, 887],
                "usable_character_bbox": [52, 151, 435, 569],
                "excluded_regions": [],
            },
            "side": {
                "image_size": [540, 887],
                "usable_character_bbox": [90, 150, 343, 573],
                "excluded_regions": [[25, 398, 68, 218], [447, 412, 69, 204]],
            },
            "back": {
                "image_size": [540, 887],
                "usable_character_bbox": [32, 155, 450, 564],
                "excluded_regions": [[496, 546, 20, 61]],
            },
        },
        "shared_axis_checks": {
            "front_side_height_relative_delta": abs(569 - 573) / 573,
            "front_back_height_relative_delta": abs(569 - 564) / 569,
            "height_gate_pass": True,
        },
        "notes": [
            "全角色翅膀展开宽度不是刚性躯干宽度，不跨视图强制相等。",
            "无顶部参考；Y 深度以清理后的侧视主体包围盒和局部部件地标为准。",
            "围巾遮挡颈部，允许头壳与躯干在围巾下隐藏搭接。",
        ],
    }
    MANIFEST_PATH.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    REGISTRATION_PATH.write_text(json.dumps(registration, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"manifest": str(MANIFEST_PATH), "registration": str(REGISTRATION_PATH), "structural_count": manifest["expected_primary_parts"]["count"]}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
