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
    remote = set()
    cities = {}
    exclusions = []
    base = {card['regionID'] for card in read(RESOURCES / 'main_characters.json')['characters']}
    reviewed = read(ROOT / 'Assets/CityBackdropSources/display-encoding-v1.json')
    photos = read(RESOURCES / 'city-scene-gallery.json')['cities']

    def city_display(group, asset_key, expected_source=None):
        entry = reviewed[group][asset_key]
        source = ROOT / entry['source']
        source_hash = hashlib.sha256(source.read_bytes()).hexdigest()
        assert source_hash == entry['sourceSHA256'], f'Source image changed: {source}'
        if expected_source is not None:
            assert source_hash == expected_source, f'Unapproved city photograph: {source}'
        file = RESOURCES / 'CityImageDisplay' / entry['file']
        assert file.stat().st_size == entry['bytes'], file
        assert hashlib.sha256(file.read_bytes()).hexdigest() == entry['sha256'], file
        return file

    for city in photos:
        name = city['id']
        if name not in base:
            cities[name] = []
        for place in city['places']:
            photo = place['photo']
            asset_name = photo['assetName']
            path = city_display('photo', asset_name, photo['outputSHA256'])
            key = 'photo/' + asset_name
            files[key] = (path, photo['outputSHA256'])
            if name not in base:
                remote.add(key)
                cities[name].append(key)

    previews = APP / 'ContentThumbnails.xcassets'
    pending_previews = set()
    for name, entry in sorted(reviewed['backdrop'].items()):
        city = name.split('_')[1]
        key = 'backdrop/' + name
        path = city_display('backdrop', name)
        files[key] = (path, None)
        if city not in base:
            remote.add(key)
            cities[city].insert(0, key)
        target = previews / f'{name}_preview.imageset'
        pending_previews.add(target.name)
        if args.update:
            from PIL import Image, ImageOps
            target.mkdir(parents=True, exist_ok=True)
            with Image.open(ROOT / entry['source']) as source:
                thumbnail = ImageOps.exif_transpose(source)
                thumbnail.thumbnail((480, 854), Image.Resampling.LANCZOS)
                thumbnail.save(target / 'preview.jpg', quality=84, optimize=True)
            (target / 'Contents.json').write_text(json.dumps({
                'images': [{'filename': 'preview.jpg', 'idiom': 'universal'}],
                'info': {'author': 'xcode', 'version': 1},
            }, indent=2) + '\n')
        assert (target / 'preview.jpg').is_file(), target
    assert len(pending_previews) == len(photos) * 5
    assert {path.name for path in previews.glob('*.imageset')} == pending_previews
    for keys in cities.values():
        keys.sort(key=lambda key: 0 if key.startswith('photo/') else 1)
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
            key = 'story/' + name
            files[key] = (path, None)
            remote.add(key)

    assets = {}
    for key, (path, source_hash) in sorted(files.items()):
        data = path.read_bytes()
        hashed_name = hashlib.sha256(data).hexdigest() + path.suffix.lower()
        assets[key] = {'file': hashed_name, 'bundleName': path.name, 'bytes': len(data)}
        if source_hash is not None:
            assets[key]['sourceSHA256'] = source_hash
        if key in remote:
            exclusions.append(path.name)
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
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        for key in sorted(remote):
            path, _ = files[key]
            target = args.output / assets[key]['file']
            if not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() != assets[key]['file'][:64]:
                shutil.copyfile(path, target)
    if args.exclusions:
        print(' '.join(exclusions))
    else:
        print(f'{len(remote)} remote assets, {len(cities)} remote cities, '
              f'{sum(assets[key]["bytes"] for key in remote):,} bytes')


if __name__ == '__main__':
    main()
