#!/usr/bin/env python3
"""Acquire attributed Commons candidates; acquisition never grants visual approval."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from hashlib import sha256
from html import unescape
from io import BytesIO
import json
from pathlib import Path
import re
import threading
import time
import urllib.parse
import urllib.request
import urllib.error
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
WORLD = ROOT / 'Content/ActivityWorld/2026-10-31-places-v1/world.json'
CACHE = ROOT / 'build/ActivityWorldPhotos'
EVIDENCE = ROOT / 'Assets/Activities/CityPlaces-v1'
NETWORK_LOCK = threading.Lock()
NEXT_REQUEST = 0.0
QUERIES = {
    'london-bloomsbury-cafe': 'Bloomsbury cafe London',
    'london-southbank': "\"Queen's Walk\" London",
    'london-borough-market': 'Borough Market London stalls',
    'london-marylebone-bookshop': 'Marylebone bookshop London',
    'london-primrose-hill': '"Primrose Hill" park skyline London -railway -tunnel' ,
    'newyork-east-village-cafe': 'East Village cafe New York',
    'newyork-greenwich-village': 'Greenwich Village New York street',
    'newyork-union-square-market': '"Union Square Greenmarket" New York' ,
    'newyork-brooklyn-bookshop': 'Brooklyn bookstore',
    'newyork-central-park': 'Central Park New York benches',
    'singapore-tiong-bahru-cafe': 'Tiong Bahru cafe Singapore',
    'singapore-joo-chiat': 'Joo Chiat Singapore street',
    'singapore-tekka-market': 'Tekka Centre Singapore market',
    'singapore-marina-bay': 'Marina Bay Singapore promenade',
    'sydney-surry-hills-cafe': 'Surry Hills Sydney cafe',
    'sydney-circular-quay': 'Circular Quay Sydney promenade',
    'sydney-glebe-market': 'Glebe Markets Sydney',
    'sydney-newtown-bookshop': 'Newtown Sydney bookshop',
    'melbourne-fitzroy-cafe': 'Fitzroy Melbourne cafe',
    'melbourne-laneways': 'Melbourne laneway street',
    'melbourne-queen-victoria-market': 'Queen Victoria Market Melbourne produce',
    'melbourne-carlton-bookshop': 'Carlton Melbourne bookshop',
    'toronto-annex-cafe': 'Annex Toronto cafe',
    'toronto-waterfront': 'Toronto waterfront promenade',
    'toronto-st-lawrence-market': 'St Lawrence Market Toronto interior',
    'toronto-distillery-district': 'Distillery District Toronto pedestrian',
    'vancouver-mount-pleasant-cafe': 'Mount Pleasant Vancouver cafe',
    'vancouver-false-creek': 'False Creek Vancouver seawall',
    'vancouver-granville-market': 'Granville Island Public Market Vancouver interior',
    'vancouver-stanley-park': 'Stanley Park Vancouver forest trail',
    'edinburgh-stockbridge-cafe': 'Stockbridge Edinburgh cafe',
    'edinburgh-old-town': 'Edinburgh Old Town street',
    'edinburgh-grassmarket': 'Grassmarket Edinburgh square',
    'dublin-portobello-cafe': 'Portobello Dublin cafe',
    'dublin-grand-canal': 'Grand Canal Dublin path',
    'dublin-georges-arcade': 'Georges Street Arcade Dublin interior',
    'auckland-ponsonby-cafe': 'Ponsonby Auckland cafe',
    'auckland-wynyard-quarter': 'Wynyard Quarter Auckland waterfront',
    'auckland-otara-market': 'Otara market Auckland',
    'capetown-observatory-cafe': 'Observatory Cape Town cafe',
    'capetown-sea-point': 'Sea Point Cape Town promenade',
    'capetown-oranjezicht-market': 'Oranjezicht City Farm Market Cape Town',
    'manchester-northern-quarter-cafe': 'Northern Quarter Manchester cafe',
    'manchester-castlefield': 'Castlefield Manchester canal towpath',
    'manchester-arndale-market': 'Arndale Market Manchester',
    'neworleans-marigny-cafe': 'Marigny New Orleans cafe',
    'neworleans-frenchmen-street': 'Frenchmen Street New Orleans',
    'neworleans-french-market': 'French Market New Orleans stalls',
    'nairobi-westlands-cafe': '"Java House" Nairobi' ,
    'nairobi-karura-forest': 'Karura Forest Nairobi trail',
    'nairobi-city-market': '"City Market" Nairobi' ,
    'kingston-new-kingston-cafe': 'New Kingston Jamaica cafe',
    'kingston-emancipation-park': 'Emancipation Park Kingston Jamaica',
    'kingston-coronation-market': 'Coronation Market Kingston Jamaica',
}


def request(url):
    global NEXT_REQUEST
    with NETWORK_LOCK:
        time.sleep(max(0, NEXT_REQUEST - time.monotonic()))
        NEXT_REQUEST = time.monotonic() + 3
    try:
        return urllib.request.urlopen(urllib.request.Request(url, headers={
            'User-Agent': 'LingoTripContent/1.0 (attributed activity-place photo research)',
        }), timeout=30).read()
    except urllib.error.HTTPError as error:
        if error.code == 429:
            delay = error.headers.get('Retry-After', '60')
            seconds = max(60, int(delay)) if delay.isdigit() else 60
            with NETWORK_LOCK:
                NEXT_REQUEST = max(NEXT_REQUEST, time.monotonic() + seconds)
        raise


def plain(value):
    return unescape(re.sub('<[^>]+>', '', value)).strip()


def acquire(place, candidate_limit):
    identifier = place['id']
    query = place.get('photoQuery') or QUERIES[identifier]
    cache = CACHE / f'{identifier}-{sha256(query.encode()).hexdigest()[:10]}-1280.json'
    if cache.exists():
        result = json.loads(cache.read_text())
    else:
        arguments = urllib.parse.urlencode({
            'action': 'query', 'format': 'json', 'generator': 'search', 'gsrsearch': query,
            'gsrnamespace': 6, 'gsrlimit': 6, 'prop': 'imageinfo',
            'iiprop': 'url|extmetadata|size', 'iiurlwidth': 1280,
        })
        result = json.loads(request('https://commons.wikimedia.org/w/api.php?' + arguments))
        cache.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    candidates = []
    for page in sorted(result.get('query', {}).get('pages', {}).values(), key=lambda item: item.get('index', 100)):
        if len(candidates) >= candidate_limit:
            break
        info = page.get('imageinfo', [{}])[0]
        metadata = info.get('extmetadata', {})
        license_name = plain(metadata.get('LicenseShortName', {}).get('value', ''))
        if not re.match(r'^(CC BY(?:-SA)? [0-9.]|CC0|Public domain)', license_name):
            continue
        url = info.get('thumburl') or info.get('url', '')
        if (not re.search(r'\.(jpe?g|png)(?:\?|$)', info.get('url', ''), re.I)
                or not re.search(r'\.(jpe?g|png)(?:\?|$)', url, re.I)):
            continue
        candidate_id = sha256(page['title'].encode()).hexdigest()[:12]
        image_path = CACHE / f'{identifier}-{candidate_id}.jpg'
        try:
            raw_path = CACHE / f'{identifier}-{candidate_id}.source'
            raw = raw_path.read_bytes() if raw_path.exists() else request(url)
            raw_path.write_bytes(raw)
            with Image.open(BytesIO(raw)) as opened:
                image = ImageOps.exif_transpose(opened).convert('RGB')
                if image.width < 800 or image.height < 500:
                    continue
                image.thumbnail((1600, 1600), Image.Resampling.LANCZOS)
                image.save(image_path, 'JPEG', quality=88, optimize=True)
                width, height = image.size
            candidates.append({
                'candidateId': candidate_id, 'placeId': identifier, 'cityId': place['cityId'],
                'fileTitle': page['title'], 'sourceUrl': info.get('descriptionurl'),
                'downloadUrl': url, 'originalUrl': info.get('url'),
                'author': plain(metadata.get('Artist', {}).get('value', 'Unknown')),
                'license': license_name,
                'licenseUrl': metadata.get('LicenseUrl', {}).get('value', ''),
                'description': plain(metadata.get('ImageDescription', {}).get('value', '')),
                'sourceSHA256': sha256(raw).hexdigest(),
                'outputSHA256': sha256(image_path.read_bytes()).hexdigest(),
                'width': width, 'height': height,
                'localPreview': str(image_path.relative_to(ROOT)),
                'processing': 'EXIF orientation; RGB; maximum 1600px; JPEG quality 88; no generated edits',
                'reviewStatus': 'draft',
            })
        except Exception as error:
            print(json.dumps({'place': identifier, 'candidate': candidate_id, 'error': str(error)}), flush=True)
    return {'placeId': identifier, 'query': query, 'candidates': candidates, 'reviewStatus': 'draft'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--city', action='append', help='Restrict to named city IDs; repeatable')
    parser.add_argument('--place', action='append', help='Restrict to specific place IDs; repeatable')
    parser.add_argument('--catalog', type=Path, default=WORLD, help='World or scene catalog containing places')
    parser.add_argument('--evidence', type=Path, default=EVIDENCE, help='Versioned candidate record directory')
    parser.add_argument('--candidate-limit', type=int, choices=range(1, 7), default=2)
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    args.evidence.mkdir(parents=True, exist_ok=True)
    world = json.loads(args.catalog.read_text())
    existing = args.evidence / 'candidates.json'
    saved = json.loads(existing.read_text()) if existing.exists() else {}
    places = [place for place in world['places'] if (not args.city or place['cityId'] in args.city) and (not args.place or place['id'] in args.place)]
    with ThreadPoolExecutor(max_workers=1) as executor:
        jobs = {executor.submit(acquire, place, args.candidate_limit): place for place in places}
        for job in as_completed(jobs):
            place = jobs[job]
            try:
                incoming = job.result()
                # New searches must not erase earlier provenance or review decisions.
                previous = saved.get(place['id'], {})
                candidates = {item['candidateId']: item for item in previous.get('candidates', [])}
                for item in incoming['candidates']:
                    old = candidates.get(item['candidateId'], {})
                    item['reviewStatus'] = old.get('reviewStatus', 'draft')
                    if 'reviewNotes' in old:
                        item['reviewNotes'] = old['reviewNotes']
                    candidates[item['candidateId']] = item
                incoming['candidates'] = list(candidates.values())
                saved[place['id']] = incoming
                print(json.dumps({'place': place['id'], 'candidates': len(saved[place['id']]['candidates'])}), flush=True)
            except Exception as error:
                previous = saved.get(place['id'], {'placeId': place['id'], 'candidates': []})
                saved[place['id']] = dict(previous, query=place.get('photoQuery') or QUERIES[place['id']], error=str(error))
                print(json.dumps({'place': place['id'], 'error': str(error)}), flush=True)
            existing.write_text(json.dumps(saved, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
