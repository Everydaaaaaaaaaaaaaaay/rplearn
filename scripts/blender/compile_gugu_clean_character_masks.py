"""从自动分割证据中生成排除相邻转面残片的完整角色实心轮廓。"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOT = ROOT / "Assets/Brand/Model/analysis/reference/segmentation-auto"
OUTPUT_ROOT = ROOT / "Assets/Brand/Model/analysis/reference/clean-character-masks"


def main() -> None:
    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    for role in ("front", "side", "back"):
        source = SOURCE_ROOT / role / "part_000_mask.png"
        mask = cv2.imread(str(source), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            raise RuntimeError(f"缺少轮廓来源：{source}")
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            raise RuntimeError(f"轮廓为空：{source}")
        largest = max(contours, key=cv2.contourArea)
        output = np.zeros_like(mask)
        cv2.drawContours(output, [largest], -1, 255, thickness=cv2.FILLED)
        cv2.imwrite(str(OUTPUT_ROOT / f"gugu-{role}-clean-silhouette.png"), output)
    print(OUTPUT_ROOT)


if __name__ == "__main__":
    main()
