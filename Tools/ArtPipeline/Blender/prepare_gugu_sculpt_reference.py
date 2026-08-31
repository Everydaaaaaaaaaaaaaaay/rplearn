"""把咕咕转面图裁成可在 Blender 正交视图中对齐的独立参考图。"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
REFERENCE_DIR = ROOT / "Assets/Brand/Model/reference"
SOURCE = REFERENCE_DIR / "gugu-turnaround-v1.png"

# 每个裁切框都保留完整角色和统一的上下基线。
CROPS = {
    "front": (20, 0, 455, 887),
    "side": (420, 0, 910, 887),
    "back": (835, 0, 1325, 887),
    "three-quarter": (1270, 0, 1774, 887),
}


def main() -> None:
    source = Image.open(SOURCE).convert("RGB")
    for name, box in CROPS.items():
        crop = source.crop(box)
        canvas = Image.new("RGB", (540, 887), (248, 246, 241))
        x = (canvas.width - crop.width) // 2
        canvas.paste(crop, (x, 0))
        output = REFERENCE_DIR / f"gugu-turnaround-v1-{name}.png"
        canvas.save(output, quality=96)
        print(output)


if __name__ == "__main__":
    main()
