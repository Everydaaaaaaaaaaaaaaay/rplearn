"""Deterministic, local color correction. No generative models or image resizing.

Run with Python 3, Pillow and NumPy from any working directory.
The immutable source is the user's FIRST full-body calibration, not later redraws.
"""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / 'source.png'
OUTPUT = ROOT / 'corrected.png'


def curve(start, segments):
    points = [start]
    p = np.array(start, dtype=float)
    for c1, c2, end in segments:
        a, b, c = map(lambda v: np.array(v, dtype=float), (c1, c2, end))
        for t in np.linspace(0, 1, 60)[1:]:
            points.append(tuple((1-t)**3*p + 3*(1-t)**2*t*a + 3*(1-t)*t*t*b + t**3*c))
        p = c
    return points


def polygon_mask(points, size):
    scale = 4
    mask = Image.new('L', (size[0]*scale, size[1]*scale))
    ImageDraw.Draw(mask).polygon([(round(x*scale), round(y*scale)) for x, y in points], fill=255)
    return np.asarray(mask.resize(size, Image.Resampling.LANCZOS), dtype=float) / 255


def main():
    im = Image.open(SOURCE)
    assert hashlib.sha256(SOURCE.read_bytes()).hexdigest() == '286f7e68e866227119451a44aeb9fbf42fb8af66fb0add061cb99a94459d86ae'
    assert im.mode == 'RGB' and im.size == (1668, 943), 'Unexpected source'
    src = np.asarray(im).copy()
    h, w = src.shape[:2]
    yy, xx = np.mgrid[:h, :w]
    rgb = src.astype(float)

    # Local coordinates only: Gaga forehead/eye-zone, ending above retained lower cheeks.
    boundary = curve((968, 391), [
        ((991, 398), (1039, 416), (1078, 414)),
        ((1100, 415), (1114, 402), (1130, 395)),
        ((1139, 389), (1149, 390), (1162, 397)),
        ((1177, 407), (1186, 415), (1205, 414)),
        ((1242, 415), (1284, 400), (1318, 391)),
    ])
    scope = polygon_mask([(990, 277), (1295, 277), (1318, 391)] + boundary[::-1], im.size)
    scope[scope < 1/255] = 0

    # Protect eye interiors; antialias the boundary against the new surrounding color.
    # Dark linework is independently protected below.
    left = curve((1023, 351), [
        ((1035, 332), (1044, 331), (1055, 332)),
        ((1075, 332), (1090, 347), (1094, 371)),
        ((1098, 394), (1086, 408), (1070, 408)),
        ((1047, 408), (1031, 398), (1026, 380)),
        ((1021, 369), (1021, 361), (1023, 351)),
    ])
    right = curve((1185, 370), [
        ((1189, 346), (1203, 333), (1221, 332)),
        ((1238, 331), (1249, 341), (1255, 354)),
        ((1260, 366), (1257, 382), (1251, 394)),
        ((1242, 405), (1227, 408), (1215, 408)),
        ((1193, 407), (1183, 395), (1185, 370)),
    ])
    eye_coverage = np.maximum(polygon_mask(left, im.size), polygon_mask(right, im.size))
    protect = eye_coverage >= 1
    # Original beak and edge must remain pixel-identical.
    beak = curve((1111, 407), [
        ((1122, 403), (1128, 391), (1140, 391)),
        ((1152, 391), (1160, 403), (1171, 407)),
        ((1161, 415), (1149, 421), (1141, 422)),
        ((1130, 419), (1119, 414), (1111, 407)),
    ])
    protect |= polygon_mask(beak, im.size) > 0.5
    protect |= rgb[..., 0] < 210

    # Fit the existing lilac field, excluding cream, outlines, eyes, beak and the background.
    X = (xx-1140)/180
    Y = (yy-345)/100
    features = np.stack([np.ones_like(X), X, Y, X*X, X*Y, Y*Y], axis=-1)
    samples = ((xx >= 976) & (xx <= 1303) & (yy >= 274) & (yy <= 386)
               & (rgb[..., 2]-rgb[..., 0] > 13) & (rgb[..., 2]-rgb[..., 1] > 23)
               & (rgb[..., 0] > 207) & (rgb[..., 0] < 226) & ~protect)
    coefficients = np.linalg.lstsq(features[samples], rgb[samples], rcond=None)[0]
    target = np.einsum('ijk,kl->ijl', features, coefficients, optimize=False)
    assert np.isfinite(target).all()

    # Cream and its edge blend are lighter than the measured lilac. Do not repaint lilac.
    amount = np.clip((rgb[..., 0]-target[..., 0]-1)/3, 0, 1)
    amount = amount*amount*(3-2*amount)
    amount *= scope
    amount *= 1-eye_coverage
    amount[protect] = 0
    amount[amount < 1/255] = 0

    out = src.copy()
    blended = np.rint(rgb*(1-amount[..., None]) + target*amount[..., None]).clip(0, 255).astype(np.uint8)
    active = amount > 0
    out[active] = blended[active]
    Image.fromarray(out).save(OUTPUT, optimize=True)
    mask = np.rint(amount*255).astype(np.uint8)
    Image.fromarray(mask).save(ROOT / 'recolor-mask.png', optimize=True)

    # Verify persisted output, not just the working array. Outside the mask must be exact.
    saved = np.asarray(Image.open(OUTPUT))
    changed = np.any(saved != src, axis=2)
    assert np.array_equal(saved[~active], src[~active])
    assert np.array_equal(saved[protect], src[protect])
    assert np.array_equal(saved[:, :850], src[:, :850])
    assert not changed[yy >= 425].any()
    allowed = (xx >= 968) & (xx <= 1320) & (yy >= 275) & (yy <= 418)
    assert not changed[~allowed].any()
    assert not changed[rgb[..., 0] < 210].any()
    cy, cx = np.where(changed)
    report = {
        'method': 'non-generative local recolor; no resampling or geometric transformation',
        'source_sha256': hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        'output_sha256': hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        'dimensions': list(im.size),
        'changed_pixels': int(changed.sum()),
        'changed_percent': round(float(changed.mean()*100), 4),
        'changed_bounds_xyxy_inclusive': [int(cx.min()), int(cy.min()), int(cx.max()), int(cy.max())],
        'changed_pixels_outside_mask': int((changed & ~active).sum()),
        'protected_eye_interiors_dark_linework_beak_changed_pixels': int((changed & protect).sum()),
        'gugu_changed_pixels': int(changed[:, :850].sum()),
        'body_below_y425_changed_pixels': int(changed[yy >= 425].sum()),
        'runtime_assets_modified': False,
    }
    (ROOT / 'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
