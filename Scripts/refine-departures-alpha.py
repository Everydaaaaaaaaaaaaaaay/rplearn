#!/usr/bin/env python3
"""Apply recorded, visually selected hair-region matte refinements.

This only removes neutral backdrop pixels in explicit review regions; it never
repaints a face, keys an entire sprite by colour, or approves the result. Raw
identity art is immutable. Run after Vision extraction; repeated runs are safe.
"""
import hashlib
import json
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'Assets/Stories/Departures/production.json'
production = json.loads(path.read_text())
for asset in production['assets']:
    review = asset.get('matte_refinement')
    if not review or not asset.get('target_path'):
        continue
    target = ROOT / asset['target_path']
    if not target.is_file():
        continue  # Retired source-only assets must never be recreated here.
    previous_hash = hashlib.sha256(target.read_bytes()).hexdigest()
    pixels = np.array(Image.open(target).convert('RGBA'))
    raw = np.array(Image.open(ROOT / asset['raw_path']).convert('RGB'))
    h, w = pixels.shape[:2]
    yy, xx = np.mgrid[:h, :w]
    x, y = xx / w, yy / h
    region = np.zeros((h, w), dtype=bool)
    for x1, y1, x2, y2 in review['regions']:
        region |= (x >= x1) & (x <= x2) & (y >= y1) & (y <= y2)
    for x1, y1, x2, y2 in review['protect']:
        region &= ~((x >= x1) & (x <= x2) & (y >= y1) & (y <= y2))
    lo, hi = raw.min(axis=2), raw.max(axis=2)
    neutral = (lo > review['minimum']) & ((hi.astype(int) - lo) < review['chroma'])
    remove = region & neutral
    pixels[remove] = 0
    # Reviewed opaque props that Vision/exterior keying accidentally removed.
    # Restore original pixels only inside the measured polygon, never redraw.
    for polygon in review.get('restore_polygons', []):
        mask = Image.new('L', (w, h))
        ImageDraw.Draw(mask).polygon([(round(px * w), round(py * h)) for px, py in polygon], fill=255)
        restore = np.array(mask) > 0
        pixels[restore, :3] = raw[restore]
        pixels[restore, 3] = 255
    Image.fromarray(pixels).save(target, optimize=True)
    asset['sha256'] = hashlib.sha256(target.read_bytes()).hexdigest()
    if asset['sha256'] != previous_hash:
        asset['status'] = 'processed-awaiting-review'
        asset.pop('visual_review', None)
path.write_text(json.dumps(production, ensure_ascii=False, indent=2) + '\n')
print('Recorded matte refinements applied; visual inspection still required.')
