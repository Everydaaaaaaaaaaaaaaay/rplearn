#!/usr/bin/env python3
"""Build a complete visual review inventory, without auto-approving artwork.

Contact sheets include retired identity masters. Sequence sheets show every
node's actual shot in script order (branch names remain visible in node IDs).
Outputs are review evidence, not an image-similarity gate or a substitute for
reading each branch. Run from any directory with Pillow installed.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=ROOT / 'build/departures-art-review')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
production = json.loads((ROOT / 'Assets/Stories/Departures/production.json').read_text())
assets = production['assets']
legacy = json.loads((ROOT / 'Assets/Stories/London/manifest.json').read_text())
assets += [dict(a, kind=a.get('kind', 'sprite' if a.get('has_alpha') else 'background')) for a in legacy['assets']]
usage = {}
scripts = []
for path in sorted((ROOT / 'App/Resources/Stories').glob('departures_*_v1.json')):
    episode = json.loads(path.read_text())
    scripts.append((path.stem, episode))
    for node in episode['nodes']:
        names = [node['shot']]
        if node.get('shotBranch'):
            names += [node['shotBranch']['yes'], node['shotBranch']['no']]
        for shot_id in set(names):
            shot = episode['shots'][shot_id]
            for name in [shot['background']] + [a['asset'] for a in shot['actors']]:
                usage.setdefault(name, []).append(f'{path.stem}:{node["id"]}:{shot_id}')

def sheets(items, prefix, columns=5, rows=3):
    for start in range(0, len(items), columns * rows):
        count = min(len(items) - start, columns * rows)
        page = Image.new('RGB', (columns * 240, ((count + columns - 1) // columns) * 396), '#e9e9e5')
        draw = ImageDraw.Draw(page)
        for offset, (picture, label) in enumerate(items[start:start + columns * rows]):
            image = picture.copy()
            image.thumbnail((234, 344))
            x, y = offset % columns * 240, offset // columns * 396
            page.paste(image, (x + (240 - image.width) // 2, y))
            draw.text((x + 4, y + 347), label, fill='#171717')
        page.save(args.output / f'{prefix}-{start // (columns * rows) + 1:02}.jpg', quality=94)

sprites = [a for a in assets if a['kind'] == 'sprite']
sheets([(Image.open(ROOT / a['raw_path']).convert('RGB'),
         a['id'] + '\n' + a['status']) for a in sprites], 'all-sprites')
for color, suffix in [('#182332', 'dark'), ('#f5f1e9', 'light')]:
    items = []
    for asset in sprites:
        path = ROOT / asset.get('target_path', '__absent__')
        if not path.is_file():
            continue
        image = Image.open(path).convert('RGBA')
        backdrop = Image.new('RGBA', image.size, color)
        backdrop.alpha_composite(image)
        items.append((backdrop.convert('RGB'), asset['id']))
    sheets(items, f'alpha-{suffix}')

def resolve(name):
    matches = list((ROOT / 'App/Resources/StoryArt').rglob(name + '.png'))
    matches += list((ROOT / 'App/Resources/StoryArt').rglob(name + '.jpg'))
    if len(matches) == 1:
        return Image.open(matches[0]).convert('RGBA')
    return None

missing = []
for chapter, episode in scripts:
    items = []
    unique, seen = [], set()
    panels = []
    for node in episode['nodes']:
        if node.get('shotBranch'):
            panels.extend((node, node['shotBranch'][key]) for key in ['yes', 'no'])
        else:
            panels.append((node, node['shot']))
    for node, shot_id in panels:
        shot = episode['shots'][shot_id]
        bg = resolve(shot['background'])
        if bg is None:
            missing.append(f'{chapter}:{node["id"]}:{shot["background"]}')
            bg = Image.new('RGBA', (390, 844), '#963737')
        canvas = ImageOps.fit(bg, (390, 844))
        for actor in shot['actors']:
            sprite = resolve(actor['asset'])
            if sprite is None:
                missing.append(f'{chapter}:{node["id"]}:{actor["asset"]}')
                continue
            height = round(min(844 * .75, 390 * 1.64) * actor['scale'])
            sprite.thumbnail((round(height * sprite.width / sprite.height), height))
            canvas.alpha_composite(sprite, (round(390 * actor['x'] - sprite.width / 2), round(844 * .51 - sprite.height / 2)))
        # Approximate native dialogue coverage, to spot hands/props hidden below it.
        shade = Image.new('RGBA', canvas.size)
        ImageDraw.Draw(shade).rectangle((0, 575, 390, 844), fill=(15, 19, 27, 175))
        canvas = Image.alpha_composite(canvas, shade)
        items.append((canvas.convert('RGB'), node['id'] + '\n' + shot_id))
        if shot_id not in seen:
            unique.append((canvas.convert('RGB'), shot_id))
            seen.add(shot_id)
    sheets(items, chapter)
    sheets(unique, chapter + '-shots')

inventory = [{k: a.get(k) for k in ['id', 'kind', 'status', 'raw_sha256', 'pose_review']}
             | {'nodes': usage.get('dp_' + a['id'], usage.get(a['id'], []))} for a in assets]
(args.output / 'inventory.json').write_text(json.dumps({'assets': inventory, 'unresolved': missing}, ensure_ascii=False, indent=2) + '\n')
print(f'{len(sprites)} sprites, {len(scripts)} sequences; {len(missing)} unresolved shot references; output: {args.output}')
