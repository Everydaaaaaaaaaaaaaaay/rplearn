"""把 mascot3d.py 的渲染结果缩到 432px，写入 DesignSystem 的 Mascot3D.xcassets。

用法（仓库根目录）：python3 Tools/ArtPipeline/Blender/mascot3d-assets.py <渲染目录>
"""
import glob
import json
import os
import shutil
import sys

from PIL import Image

SIZE = 432  # 144pt@3x，覆盖 App 里常用的吉祥物尺寸。
source = sys.argv[1]
catalog = "Packages/LingoKit/Sources/DesignSystem/Resources/Mascot3D.xcassets"
if os.path.isdir(catalog):
    shutil.rmtree(catalog)
os.makedirs(catalog)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(catalog, "Contents.json"), "w"), indent=2)
for path in sorted(glob.glob(os.path.join(source, "*.png"))):
    name = "mascot-" + os.path.basename(path)[:-4]
    folder = os.path.join(catalog, name + ".imageset")
    os.makedirs(folder)
    image = Image.open(path).convert("RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    image.save(os.path.join(folder, name + ".png"), optimize=True)
    json.dump({
        "images": [{"filename": name + ".png", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
    }, open(os.path.join(folder, "Contents.json"), "w"), indent=2)
    print(name)
