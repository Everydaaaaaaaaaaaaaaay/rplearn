#!/usr/bin/env python3
"""Produce same-resolution city display images and the per-image quality record."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

import numpy as np
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
RESOURCES = ROOT / 'App/Resources'
SOURCES = ROOT / 'Assets/CityBackdropSources'
TARGET = RESOURCES / 'CityImageDisplay'
RECORD = SOURCES / 'display-encoding-v1.json'
FRAMING = RESOURCES / 'activity-photo-framing.json'
RESAMPLE = Image.Resampling.LANCZOS


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgb(path):
    with Image.open(path) as source:
        return ImageOps.exif_transpose(source).convert('RGB')


def phone_view(image, position):
    return np.asarray(ImageOps.fit(image, (1170, 2532), method=RESAMPLE, centering=(position, 0.5)), dtype=np.float32)


def quality_measures(original, mobile, candidate, position):
    error = np.square(mobile - phone_view(candidate, position))
    mse = float(error.mean())
    worst_tile = max(float(error[top:top + 390, left:left + 390].mean())
                     for top in range(0, 2532, 390) for left in range(0, 1170, 390))
    full = original.copy()
    display = candidate.copy()
    full.thumbnail((1470, 1470), RESAMPLE)
    display.thumbnail((1470, 1470), RESAMPLE)
    full_error = float(np.square(np.asarray(full, dtype=np.float32) - np.asarray(display, dtype=np.float32)).mean())
    psnr = lambda value: min(99.0, 10 * math.log10(255 * 255 / max(value, 1e-9)))
    return psnr(mse), psnr(worst_tile), psnr(full_error)


def encode(task):
    kind, key, path, position, output = task
    original = rgb(path)
    original_bytes = path.stat().st_size
    mobile = phone_view(original, position)
    qualities = (90, 93, 95) if kind == 'backdrop' else (93, 95, 97)
    threshold = (40, 36, 40) if kind == 'backdrop' else (42, 38, 42)
    with TemporaryDirectory() as scratch:
        temporary = Path(scratch) / 'candidate.webp'
        for quality in qualities:
            subprocess.run(['cwebp', '-quiet', '-m', '5', '-sharp_yuv', '-metadata', 'all', '-q',
                            str(quality), str(path), '-o', str(temporary)], check=True)
            if temporary.stat().st_size > original_bytes * 0.88:
                break
            candidate = rgb(temporary)
            assert candidate.size == original.size
            with Image.open(path) as source, Image.open(temporary) as encoded:
                assert source.info.get('icc_profile') == encoded.info.get('icc_profile')
                assert source.getexif().get(274, 1) == encoded.getexif().get(274, 1)
            measured = quality_measures(original, mobile, candidate, position)
            if all(actual >= minimum for actual, minimum in zip(measured, threshold)):
                destination = output / f'display-{path.stem}.webp'
                shutil.copyfile(temporary, destination)
                return kind, key, record(path, destination, original.size, quality, measured)
    destination = output / f'display-{path.stem}.jpg'
    shutil.copyfile(path, destination)
    return kind, key, record(path, destination, original.size, None, None)


def record(source, destination, size, grade, measured):
    return {
        'source': str(source.relative_to(ROOT)),
        'sourceSHA256': digest(source),
        'sourceBytes': source.stat().st_size,
        'file': destination.name,
        'sha256': digest(destination),
        'bytes': destination.stat().st_size,
        'pixels': list(size),
        'webpQuality': grade,
        'screenPSNR': round(measured[0], 2) if measured else None,
        'worstScreenTilePSNR': round(measured[1], 2) if measured else None,
        'fullViewPSNR': round(measured[2], 2) if measured else None,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', type=int, default=4)
    args = parser.parse_args()
    assert 1 <= args.jobs <= 8
    framing = json.loads(FRAMING.read_text())
    jobs = []
    for folder in sorted(SOURCES.glob('*.xcassets/*.imageset')):
        file = json.loads((folder / 'Contents.json').read_text())['images'][0]['filename']
        jobs.append(('backdrop', folder.stem, folder / file, 0.5))
    for path in sorted((RESOURCES / 'ActivityPlacesGallery').glob('*.jpg')):
        anchors = {'leading': 0, 'center': 0.5, 'trailing': 1}
        value = framing.get(path.name, '0.5')
        position = anchors[value] if value in anchors else float(value)
        jobs.append(('photo', path.name, path, position))
    assert len(jobs) == 129
    with TemporaryDirectory(dir=RESOURCES, prefix='.city-image-encode-') as scratch:
        staging = Path(scratch)
        results = {'backdrop': {}, 'photo': {}}
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            for group, key, result in pool.map(encode, [(a, b, c, d, staging) for a, b, c, d in jobs]):
                results[group][key] = result

        TARGET.mkdir(exist_ok=True)
        for path in staging.iterdir():
            path.replace(TARGET / path.name)
        selected = {item['file'] for group in results.values() for item in group.values()}
        for path in TARGET.glob('display-*'):
            if path.name not in selected:
                path.unlink()
        RECORD.write_text(json.dumps(results, sort_keys=True, indent=2) + '\n')
        for name, group in results.items():
            print(name, len(group), 'webp', sum(item['webpQuality'] is not None for item in group.values()),
                  'original bytes', sum(item['sourceBytes'] for item in group.values()),
                  'display bytes', sum(item['bytes'] for item in group.values()))


if __name__ == '__main__':
    main()
