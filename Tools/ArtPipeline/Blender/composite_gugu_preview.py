"""把 Blender 的透明渲染合成到品牌预览背景上。"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[3]
RENDER_DIR = ROOT / "Assets/Brand/Model/renders"
SOURCE = RENDER_DIR / "gugu-model-v1-front-transparent.png"
OUTPUT = RENDER_DIR / "gugu-model-v1-front.png"
BACKGROUND = (247, 244, 239, 255)


def main() -> None:
    foreground = Image.open(SOURCE).convert("RGBA")
    background = Image.new("RGBA", foreground.size, BACKGROUND)
    background.alpha_composite(foreground)
    background.convert("RGB").save(OUTPUT, quality=95)
    print(f"GUGU_PREVIEW_SAVED={OUTPUT}")


if __name__ == "__main__":
    main()
