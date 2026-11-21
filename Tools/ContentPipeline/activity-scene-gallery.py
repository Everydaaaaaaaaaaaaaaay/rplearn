#!/usr/bin/env python3
"""Build or verify the reviewed, bundled city scene gallery without publishing a world."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import shutil
from urllib.parse import urlparse
from PIL import Image
from activity_photo_quality import has_screen_resolution

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / 'Assets/Activities/CityPlaces-v2'
ASSETS = ROOT / 'App/Resources/ActivityPlacesGallery'
MANIFEST = ROOT / 'App/Resources/city-scene-gallery.json'
FRAMING = ROOT / 'App/Resources/activity-photo-framing.json'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', action='store_true', help='Copy reviewed files and write the app manifest')
    args = parser.parse_args()
    catalog = json.loads((EVIDENCE / 'catalog.json').read_text())
    selection = json.loads((EVIDENCE / 'selected-photos.json').read_text())
    places = catalog['places']
    photos = {photo['placeId']: photo for photo in selection['photos']}
    assert len(photos) == len(selection['photos']), 'Duplicate photo assignment'
    assert set(photos) == {place['id'] for place in places}, 'Photo coverage differs from the catalog'
    assert len({photo['outputSHA256'] for photo in photos.values()}) == len(photos), 'Reused scene photograph'
    regions = json.loads((ROOT / 'App/Resources/regions.json').read_text())['regions']
    assert {city['id'] for city in catalog['cities']} == {region['id'] for region in regions}, 'City coverage differs'
    assert len({place['id'] for place in places}) == len(places), 'Duplicate place ID'
    assert {place['cityId'] for place in places} <= {city['id'] for city in catalog['cities']}, 'Unknown city'
    expected = {'schemaVersion': 1, 'version': catalog['version'], 'cities': []}
    framing = {}
    for city in catalog['cities']:
        city_places = [place for place in places if place['cityId'] == city['id']]
        assert 3 <= len(city_places) <= 5, f"Invalid scene count for {city['id']}"
        compiled = []
        for place in city_places:
            photo = photos[place['id']]
            assert photo['cityId'] == city['id'], 'Photo city mismatch'
            assert photo['reviewStatus'] == 'preview-approved' and photo['reviewNotes'], 'Unreviewed photograph'
            assert photo['spatialNotes'], 'Missing scene-specific spatial constraints'
            for field in ['sourceUrl', 'licenseUrl']:
                assert urlparse(photo[field]).scheme == 'https' and urlparse(photo[field]).netloc, field
            assert photo['author'] and photo['license'], 'Missing attribution'
            asset_name = f"scene-{place['id']}-v2.jpg"
            alignment = place.get('photoAlignment', 'center')
            assert alignment in ['leading', 'center', 'trailing'], 'Unknown photo framing'
            position = place.get('photoHorizontalPosition')
            if position is not None:
                assert type(position) in (int, float) and 0 <= position <= 1, 'Invalid photo focal position'
                framing[asset_name] = str(position)
            elif alignment != 'center':
                framing[asset_name] = alignment
            destination = ASSETS / asset_name
            if args.build:
                source = ROOT / photo['localPreview']
                if not source.exists():
                    source = destination
                assert sha256(source.read_bytes()).hexdigest() == photo['outputSHA256'], 'Source hash mismatch'
                ASSETS.mkdir(parents=True, exist_ok=True)
                if source.resolve() != destination.resolve():
                    shutil.copyfile(source, destination)
            assert sha256(destination.read_bytes()).hexdigest() == photo['outputSHA256'], str(destination)
            with Image.open(destination) as image:
                assert image.format == 'JPEG' and image.size == (photo['width'], photo['height']), str(destination)
                assert has_screen_resolution(image.width, image.height), 'Insufficient full-screen portrait pixels'
                image.verify()
            public_photo = {key: photo[key] for key in [
                'cityId', 'placeId', 'sourceUrl', 'author', 'license', 'licenseUrl', 'outputSHA256', 'width', 'height',
            ]}
            public_photo.update(id=f"photo-{place['id']}-v2", assetName=asset_name)
            compiled.append({key: place[key] for key in ['id', 'titleZh', 'category', 'descriptionZh']} | {'photo': public_photo})
        expected['cities'].append(dict(id=city['id'], nameZh=city['nameZh'], places=compiled))
    if args.build:
        MANIFEST.write_text(json.dumps(expected, ensure_ascii=False, indent=2) + '\n')
        FRAMING.write_text(json.dumps(framing, ensure_ascii=False, indent=2) + '\n')
    assert json.loads(MANIFEST.read_text()) == expected, 'Bundled gallery manifest differs from reviewed content'
    assert json.loads(FRAMING.read_text()) == framing, 'Bundled photo framing differs'
    expected_assets = {place['photo']['assetName'] for city in expected['cities'] for place in city['places']}
    assert {path.name for path in ASSETS.iterdir()} == expected_assets, 'Unexpected or stale gallery files'
    print(json.dumps({'cities': len(expected['cities']), 'scenes': len(places), 'uniquePhotos': len(photos), 'status': 'verified'}))


if __name__ == '__main__':
    main()
