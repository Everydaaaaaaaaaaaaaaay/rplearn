"""把 seeded masks 转换成用于轮廓门禁的无孔实心外轮廓。"""

from __future__ import annotations

from pathlib import Path

import cv2
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = ROOT / "Assets/Brand/Model/analysis/reference/front-parts"
OUTPUT_DIR = ROOT / "Assets/Brand/Model/analysis/reference/front-contract-masks"


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    for source in SOURCE_DIR.glob("*_mask.png"):
        mask = cv2.imread(str(source), cv2.IMREAD_GRAYSCALE)
        if mask is None:
            continue
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        filled = np.zeros_like(mask)
        if contours:
            cv2.drawContours(filled, contours, -1, 255, thickness=cv2.FILLED)
        output = OUTPUT_DIR / source.name.replace("_mask.png", "_silhouette.png")
        cv2.imwrite(str(output), filled)
    print(OUTPUT_DIR)


if __name__ == "__main__":
    main()
