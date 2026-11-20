#!/usr/bin/env python3
"""Verify or export the immutable assets for the optional slim iOS build."""
import argparse
import hashlib
import json
import re
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'App'
RESOURCES = APP / 'Resources'
MANIFEST = RESOURCES / 'downloadable-content.json'


def read(path):
    return json.loads(path.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update', action='store_true', help='Regenerate the catalog and compact offline thumbnails')
    parser.add_argument('--output', type=Path, help='Emit the immutable files for static hosting')
    parser.add_argument('--exclusions', action='store_true', help='Print the Xcode resource exclusions')
    args = parser.parse_args()

    files = {}
    cities = {}
    exclusions = ['RemoteCityBackdrops.xcassets']
    base = {card['regionID'] for card in read(RESOURCES / 'main_characters.json')['characters']}
    photos = read(RESOURCES / 'city-scene-gallery.json')['cities']
    for city in photos:
        name = city['id']
        if name in base:
            continue
        keys = []
        for place in city['places']:
            photo = place['photo']
            path = RESOURCES / 'ActivityPlacesGallery' / photo['assetName']
            assert hashlib.sha256(path.read_bytes()).hexdigest() == photo['outputSHA256'], path
            key = 'photo/' + path.name
            files[key] = path
            keys.append(key)
            exclusions.append(path.name)
        cities[name] = keys

    previews = APP / 'ContentThumbnails.xcassets'
    pending_previews = set()
    for imageset in sorted((APP / 'RemoteCityBackdrops.xcassets').glob('*.imageset')):
        name = imageset.stem
        city = name.split('_')[1]
        assert city in cities
        image = read(imageset / 'Contents.json')['images'][0]['filename']
        key = 'backdrop/' + name
        path = imageset / image
        files[key] = path
        cities[city].insert(0, key)
        target = previews / f'{name}_preview.imageset'
        pending_previews.add(target.name)
        if args.update:
            from PIL import Image, ImageOps
            target.mkdir(parents=True, exist_ok=True)
            with Image.open(path) as source:
                thumbnail = ImageOps.exif_transpose(source)
                thumbnail.thumbnail((360, 640), Image.Resampling.LANCZOS)
                thumbnail.save(target / 'preview.jpg', quality=84, optimize=True)
            (target / 'Contents.json').write_text(json.dumps({
                'images': [{'filename': 'preview.jpg', 'idiom': 'universal'}],
                'info': {'author': 'xcode', 'version': 1},
            }, indent=2) + '\n')
        assert (target / 'preview.jpg').is_file(), target
    assert len(pending_previews) == len(cities) * 5
    assert {path.name for path in previews.glob('*.imageset')} == pending_previews
    for keys in cities.values():
        keys.sort(key=lambda key: 0 if key.startswith('photo/') else 1)
        # This is the first scene visible when the traveler opens the city.
        first = keys.pop(0)
        keys.sort(key=lambda key: 0 if key.startswith('backdrop/activities_') else 1)
        keys.insert(0, first)

    art = {path.stem: path for path in (RESOURCES / 'StoryArt').rglob('*')
           if path.suffix in {'.jpg', '.png', '.webp'}}
    keep = {'avatar_oliver'}
    for path in (RESOURCES / 'Stories').rglob('*.json'):
        if not re.fullmatch(r'departures_(?:london|mainline_newyork|mainline_melbourne)_v\d+', path.stem):
            continue
        for shot in read(path)['shots'].values():
            keep.add(shot['background'])
            keep.update(actor['asset'] for actor in shot.get('actors', []))
    for name, path in sorted(art.items()):
        if name not in keep:
            files['story/' + name] = path
            exclusions.append(path.name)

    assets = {}
    for key, path in sorted(files.items()):
        data = path.read_bytes()
        hashed_name = hashlib.sha256(data).hexdigest() + path.suffix.lower()
        assets[key] = {'file': hashed_name, 'bytes': len(data)}
        if args.output:
            args.output.mkdir(parents=True, exist_ok=True)
            target = args.output / hashed_name
            if not target.exists() or target.read_bytes() != data:
                shutil.copyfile(path, target)
    openings = {}
    for path in sorted((RESOURCES / 'Stories').rglob('*.json')):
        episode = read(path)
        if 'shots' not in episode:
            continue
        node = next(node for node in episode['nodes'] if node['id'] == episode['start'])
        shot = episode['shots'][node['shot']]
        names = [shot['background'], *(actor['asset'] for actor in shot.get('actors', []))]
        keys = ['story/' + name for name in names if 'story/' + name in assets]
        if keys:
            openings[episode['id']] = keys
    expected = {'assets': assets, 'cities': cities, 'openings': openings}
    if args.update:
        MANIFEST.write_text(json.dumps(expected, sort_keys=True, indent=2) + '\n')
    assert read(MANIFEST) == expected, 'Run ios-content-packs.py --update after changing packaged artwork'
    if args.exclusions:
        print(' '.join(exclusions))
    else:
        print(f'{len(assets)} originals, {len(cities)} remote cities, {sum(a["bytes"] for a in assets.values()):,} bytes')


if __name__ == '__main__':
    main()
