"""Read-only image/asset checks. Never recolors, resizes or edits a PNG."""
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / 'manifest.json').read_text())
report = []
assert len(manifest['assets']) == 8
assert len({a['assetName'] for a in manifest['assets']}) == 8
for asset in manifest['assets']:
    path = ROOT / asset['path']
    with Image.open(path) as image:
        image.load()
        assert image.mode == 'RGBA', path
        assert image.size == (1254, 1254), path
        alpha = image.getchannel('A')
        hist = alpha.histogram()
        assert hist[0] > 0 and hist[255] > 0
        assert sum(hist[1:255]) > 0, 'Expected antialiased alpha edges'
        opaque = alpha.point(lambda value: 255 if value > 128 else 0)
        x0, y0, x1, y1 = opaque.getbbox()
        assert x0 > 0 and y0 > 0 and x1 < image.width and y1 < image.height, path
        contents = json.loads((path.parent / 'Contents.json').read_text())
        entries = [item for item in contents['images'] if 'filename' in item]
        assert entries == [{'filename': path.name, 'idiom': 'universal', 'scale': '3x'}]
        report.append({
            'id': asset['id'], 'mode': image.mode, 'size': list(image.size),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            'bytes': path.stat().st_size,
            'fully_transparent_percent': round(hist[0] / (image.width * image.height) * 100, 2),
            'opaque_bounds_xyxy_exclusive': [x0, y0, x1, y1],
            'opaque_pixels_touch_border': False,
        })
print(json.dumps({'assets': report, 'total_bytes': sum(a['bytes'] for a in report),
                  'pixel_edits_applied': False,
                  'runtime_integrated': bool(manifest.get('runtimeIntegrated', False))}, indent=2))
