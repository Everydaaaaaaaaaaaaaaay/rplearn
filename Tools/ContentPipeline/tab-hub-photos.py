#!/usr/bin/env python3
"""Build and verify the two independently sourced hub backgrounds for every city."""
import argparse
from hashlib import sha256
from html import unescape
import json
from pathlib import Path
import re
from urllib.parse import unquote, urlparse
from PIL import Image, ImageOps
from activity_photo_quality import has_screen_resolution, display_scale

ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / 'Assets/TabHubScenes/2026-11-16-v1'
MANIFEST = ROOT / 'App/Resources/hub-scene-photos.json'
ASSETS = ROOT / 'App/Assets.xcassets'
REMOTE_ASSETS = ROOT / 'App/RemoteCityBackdrops.xcassets'


def source_key(value):
    value = unquote(unescape(value)).replace('_', ' ').strip().lower()
    if 'file:' in value:
        return value.split('file:', 1)[1].split('?', 1)[0]
    return value.rstrip('/')


def existing_sources():
    paths = [
        ROOT / 'Assets/CityTabScenes/Review-2026-09-12/after.json',
        ROOT / 'Assets/CityTabScenes/Review-2026-09-12/before.json',
        ROOT / 'Assets/LearningCityScenes/Review-2026-10-27/photos.json',
        ROOT / 'Assets/Activities/CityPlaces-v2/selected-photos.json',
        ROOT / 'Assets/Activities/CityPlaces-v1/preview-photos.json',
        ROOT / 'App/Resources/activity-world-release.json',
        ROOT / 'App/Resources/city-scene-gallery.json',
    ]
    sources = set()
    def visit(value):
        if isinstance(value, dict):
            for item in value.values():
                visit(item)
        elif isinstance(value, list):
            for item in value:
                visit(item)
        elif isinstance(value, str) and (value.startswith('https://') or value.startswith('File:')):
            sources.add(source_key(value))
    for path in paths:
        if path.exists():
            visit(json.loads(path.read_text()))
    credits = ROOT / 'Packages/LingoKit/Sources/SettingsFeature/CityScenePhotoCreditsView.swift'
    for url in re.findall(r'https://[^"\s]+', credits.read_text()):
        sources.add(source_key(url))
    return sources


def render(photo, destination):
    path = ROOT / photo['localSource']
    raw = path.read_bytes()
    assert sha256(raw).hexdigest() == photo['sourceSHA256'], f'Source bytes changed for {photo["id"]}'
    with Image.open(path) as opened:
        image = ImageOps.exif_transpose(opened).convert('RGB')
        width, height = image.size
        target_ratio = 9 / 16
        crop_width = min(width, round(height * target_ratio))
        crop_height = min(height, round(width / target_ratio))
        left = round((width - crop_width) * photo.get('horizontalPosition', 0.5))
        top = round((height - crop_height) * photo.get('verticalPosition', 0.5))
        crop = (left, top, left + crop_width, top + crop_height)
        image = image.crop(crop)
        image.thumbnail((1620, 2880), Image.Resampling.LANCZOS)
        assert has_screen_resolution(*image.size), f'Insufficient portrait pixels for {photo["id"]}'
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination, 'JPEG', quality=94, subsampling=0, optimize=True)
        return dict(cropBoxInDownloadedPixels=list(crop), downloadedSize=[width, height],
                    width=image.width, height=image.height, outputSHA256=sha256(destination.read_bytes()).hexdigest(),
                    processing='EXIF orientation; RGB; native 9:16 crop; downsample only to at most 1620x2880; JPEG quality 94, 4:4:4')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true')
    args = parser.parse_args()
    catalog = json.loads((RECORD / 'catalog.json').read_text())
    selection_path = RECORD / 'selected-photos.json'
    selection = json.loads(selection_path.read_text())
    photos = selection['photos']
    places = {place['id']: place for place in catalog['places']}
    regions = {region['id'] for region in json.loads((ROOT / 'App/Resources/regions.json').read_text())['regions']}
    assert len(photos) == len(places) == len(regions) * 2
    assert {photo['id'] for photo in photos} == set(places)
    assert {(photo['cityID'], photo['role']) for photo in photos} == {(city, role) for city in regions for role in ['activities', 'profile']}
    used = existing_sources()
    assert all(source_key(photo['sourceURL']) not in used and source_key(photo['fileTitle']) not in used for photo in photos), 'A previously used photograph was selected'
    assert len({source_key(photo['sourceURL']) for photo in photos}) == len(photos), 'Duplicate source photograph'
    assert len({photo['sourceSHA256'] for photo in photos}) == len(photos), 'Duplicate downloaded image'
    compiled = []
    starters = {card['regionID'] for card in json.loads((ROOT / 'App/Resources/main_characters.json').read_text())['characters']}
    for photo in photos:
        assert photo['cityID'] == places[photo['id']]['cityId']
        assert photo['reviewNotes'] and photo['cityEvidence'] and photo['placementNotes']
        assert photo['reviewStatus'] in ['source-reviewed', 'approved']
        assert photo['author'] and photo['license']
        for name in ['sourceURL', 'licenseURL']:
            assert urlparse(photo[name]).scheme == 'https' and urlparse(photo[name]).netloc
        asset = f'{photo["role"]}_{photo["cityID"]}_glass'
        catalog_path = ASSETS if photo['cityID'] in starters else REMOTE_ASSETS
        destination = catalog_path / f'{asset}.imageset' / f'{asset}.jpg'
        if args.build:
            photo.update(render(photo, destination))
            contents = {'images': [{'filename': destination.name, 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}
            (destination.parent / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n')
        assert sha256(destination.read_bytes()).hexdigest() == photo['outputSHA256']
        with Image.open(destination) as image:
            assert image.format == 'JPEG' and list(image.size) == [photo['width'], photo['height']]
            assert has_screen_resolution(*image.size)
            image.verify()
        photo['referenceDisplayScale'] = display_scale(photo['width'], photo['height'])
        value = {key: photo[key] for key in ['cityID', 'cityName', 'role', 'title', 'author', 'license', 'sourceURL', 'licenseURL', 'width', 'height', 'outputSHA256']}
        compiled.append(dict(value, assetName=asset))
    assert len({photo['outputSHA256'] for photo in photos}) == len(photos)
    manifest = {'schemaVersion': 1, 'version': selection['version'], 'photos': compiled}
    if args.build:
        MANIFEST.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
        selection_path.write_text(json.dumps(selection, ensure_ascii=False, indent=2) + '\n')
    assert json.loads(MANIFEST.read_text()) == manifest
    audit = {'cities': len(regions), 'photos': len(photos), 'uniqueSources': len({source_key(photo['sourceURL']) for photo in photos}),
             'existingSourceKeysChecked': len(used), 'previousSourceReuse': 0,
             'maximumReferenceDisplayScale': max(photo['referenceDisplayScale'] for photo in photos), 'status': 'verified'}
    (RECORD / 'reuse-resolution-audit.json').write_text(json.dumps(audit, indent=2) + '\n')
    print(json.dumps(audit))


if __name__ == '__main__':
    main()
