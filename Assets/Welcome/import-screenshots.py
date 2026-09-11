#!/usr/bin/env python3
"""Import physical iPhone screenshots: rectangular crop + JPEG encoding only."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

source = Path(sys.argv[1])
root = Path(__file__).resolve().parents[2]
# y, x, height, width in the original 1170 × 2532 screen capture.
regions = {
    'activity': (1070, 0, 1130, 1170),
    'chat': (880, 0, 1220, 1170),
    'dictionary': (810, 0, 1320, 1170),
    'companion': (700, 70, 1250, 1030),
}
records = []
for name, rect in regions.items():
    for theme in ['light', 'dark']:
        stem = f'welcome-{name}-{theme}'
        original = source / f'{stem}.png'
        folder = root / 'App/Assets.xcassets' / f'{stem}.imageset'
        folder.mkdir(exist_ok=True)
        target = folder / 'screenshot.jpg'
        y, x, h, w = rect
        subprocess.run(['sips', '-c', str(h), str(w), '--cropOffset', str(y), str(x),
                        '-s', 'format', 'jpeg', '-s', 'formatOptions', '85',
                        str(original), '--out', str(target)], check=True, stdout=subprocess.DEVNULL)
        (folder / 'Contents.json').write_text(json.dumps({
            'images': [{'filename':'screenshot.jpg','idiom':'universal'}],
            'info': {'author':'xcode','version':1}
        }, indent=2) + '\n')
        records.append({'asset':stem, 'sourceSHA256':hashlib.sha256(original.read_bytes()).hexdigest(),
                        'cropYXHW':rect, 'jpegBytes':target.stat().st_size,
                        'assetSHA256':hashlib.sha256(target.read_bytes()).hexdigest()})
(root / 'Assets/Welcome/captures-v1.json').write_text(json.dumps({
    'device':'physical iPhone 13', 'resolution':[1170,2532], 'date':'2026-09-12',
    'captureTool':'Xcode devicectl device capture screenshot',
    'data':'isolated in-memory showcase account; bundled starter characters; sample chat and example translations',
    'records':records
}, ensure_ascii=False, indent=2)+'\n')
print('Total JPEG bytes:', sum(r['jpegBytes'] for r in records))
