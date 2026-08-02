"""从咕咕三视图中提取稳定的颜色/区域地标，供 Blender 自动拟合使用。"""

from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
REFERENCE_DIR = ROOT / "Assets/Brand/Model/reference"
OUTPUT = ROOT / "Assets/Brand/Model/analysis/reference/gugu-landmarks.auto.json"


def hsv_mask(image: np.ndarray, bands: list[tuple[tuple[int, int, int], tuple[int, int, int]]]) -> np.ndarray:
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    result = np.zeros(image.shape[:2], np.uint8)
    for lower, upper in bands:
        result = cv2.bitwise_or(
            result,
            cv2.inRange(hsv, np.array(lower, np.uint8), np.array(upper, np.uint8)),
        )
    return result


def largest_region(mask: np.ndarray, roi: tuple[int, int, int, int], min_area: int = 20) -> dict:
    x, y, width, height = roi
    clipped = np.zeros_like(mask)
    clipped[y : y + height, x : x + width] = mask[y : y + height, x : x + width]
    clipped = cv2.morphologyEx(clipped, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(clipped, 8)
    candidates = [(int(stats[i, cv2.CC_STAT_AREA]), i) for i in range(1, count)]
    candidates = [item for item in candidates if item[0] >= min_area]
    if not candidates:
        return {"roi": list(roi), "empty": True}
    area, index = max(candidates)
    bx = int(stats[index, cv2.CC_STAT_LEFT])
    by = int(stats[index, cv2.CC_STAT_TOP])
    bw = int(stats[index, cv2.CC_STAT_WIDTH])
    bh = int(stats[index, cv2.CC_STAT_HEIGHT])
    return {
        "roi": list(roi),
        "area_px": area,
        "bbox_px": [bx, by, bw, bh],
        "centroid_px": [float(centroids[index, 0]), float(centroids[index, 1])],
    }


def analyze_front(image: np.ndarray) -> dict:
    masks = {
        "blue": hsv_mask(image, [((85, 45, 55), (115, 255, 255))]),
        "red": hsv_mask(image, [((0, 95, 55), (9, 255, 255)), ((170, 80, 55), (179, 255, 255))]),
        "gold": hsv_mask(image, [((13, 70, 55), (35, 255, 255))]),
        "orange": hsv_mask(image, [((0, 95, 55), (16, 255, 255))]),
        "cream": hsv_mask(image, [((4, 5, 125), (32, 125, 255))]),
        "dark": hsv_mask(image, [((0, 0, 0), (179, 255, 105))]),
    }
    specs = {
        "head_blue": ("blue", (120, 185, 330, 245), 1000),
        "crest_blue": ("blue", (215, 135, 155, 100), 100),
        "torso_blue": ("blue", (130, 425, 290, 255), 1000),
        "wing_left": ("blue", (45, 420, 145, 225), 300),
        "wing_right": ("blue", (355, 420, 140, 220), 300),
        "eye_left": ("dark", (180, 285, 85, 100), 100),
        "eye_right": ("dark", (315, 285, 85, 100), 100),
        "brow_left": ("dark", (180, 280, 90, 45), 50),
        "brow_right": ("dark", (315, 280, 90, 45), 50),
        "beak": ("orange", (245, 335, 90, 85), 200),
        "cheek_left": ("cream", (145, 300, 145, 150), 200),
        "cheek_right": ("cream", (285, 300, 140, 150), 200),
        "scarf": ("red", (145, 380, 345, 130), 500),
        "belly_patch": ("cream", (145, 450, 230, 225), 500),
        "bag": ("gold", (300, 500, 155, 180), 500),
        "strap": ("gold", (160, 400, 255, 200), 300),
        "foot_left": ("orange", (165, 665, 105, 65), 100),
        "foot_right": ("orange", (285, 665, 110, 65), 100),
    }
    return {name: largest_region(masks[color], roi, area) for name, (color, roi, area) in specs.items()}


def analyze_side(image: np.ndarray) -> dict:
    masks = {
        "blue": hsv_mask(image, [((85, 45, 55), (115, 255, 255))]),
        "red": hsv_mask(image, [((0, 95, 55), (9, 255, 255)), ((170, 80, 55), (179, 255, 255))]),
        "orange": hsv_mask(image, [((0, 95, 55), (16, 255, 255))]),
        "gold": hsv_mask(image, [((13, 70, 55), (35, 255, 255))]),
    }
    specs = {
        "head_depth": ("blue", (105, 180, 295, 255), 1000),
        "torso_depth": ("blue", (160, 425, 280, 260), 1000),
        "wing": ("blue", (250, 420, 195, 225), 500),
        "tail": ("blue", (330, 560, 115, 110), 100),
        "beak": ("orange", (85, 325, 95, 85), 100),
        "scarf": ("red", (115, 375, 330, 135), 500),
        "bag": ("gold", (105, 470, 195, 205), 500),
    }
    return {name: largest_region(masks[color], roi, area) for name, (color, roi, area) in specs.items()}


def analyze_back(image: np.ndarray) -> dict:
    masks = {
        "blue": hsv_mask(image, [((85, 45, 55), (115, 255, 255))]),
        "red": hsv_mask(image, [((0, 95, 55), (9, 255, 255)), ((170, 80, 55), (179, 255, 255))]),
        "gold": hsv_mask(image, [((13, 70, 55), (35, 255, 255))]),
    }
    specs = {
        "head_back": ("blue", (110, 175, 315, 255), 1000),
        "torso_back": ("blue", (130, 420, 335, 265), 1000),
        "wing_left_back": ("blue", (25, 430, 170, 220), 300),
        "wing_right_back": ("blue", (350, 430, 145, 220), 300),
        "scarf_back": ("red", (60, 390, 335, 140), 500),
        "bag_back": ("gold", (95, 440, 150, 230), 500),
        "strap_back": ("gold", (145, 410, 250, 220), 300),
    }
    return {name: largest_region(masks[color], roi, area) for name, (color, roi, area) in specs.items()}


def main() -> None:
    analyzers = {"front": analyze_front, "side": analyze_side, "back": analyze_back}
    report = {
        "schema": "gugu_reference_landmarks.v1",
        "coordinate_system": "pixel origin top-left; image size 540x887",
        "views": {},
    }
    for role, analyzer in analyzers.items():
        path = REFERENCE_DIR / f"gugu-turnaround-v1-{role}.png"
        image = cv2.imread(str(path))
        if image is None:
            raise RuntimeError(f"无法读取参考图：{path}")
        report["views"][role] = {
            "source": str(path),
            "image_size": [int(image.shape[1]), int(image.shape[0])],
            "landmarks": analyzer(image),
        }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(OUTPUT)


if __name__ == "__main__":
    main()
