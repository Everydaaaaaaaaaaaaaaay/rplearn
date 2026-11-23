"""把十五城活动地点的实拍照片做成“出去走走”的竖版风格化场景。

每个地点输出两张图（写入 App/Resources/StylizedPlaces/）：
- styled-place-<id>.webp：竖版风格化照片，天空抠成透明，App 在底下画会动的天空；
- styled-place-<id>-motion.png：低分辨率动态遮罩，R=树叶、G=水面、B=远近（1 为最近），
  App 的着色器据此让树叶摇、水面起波光，并按远近做轻微视差。

处理全部是确定性的：语义分割（SegFormer ADE20K）与单目深度（DPT）只做分析、不生成像素；
其余是裁切、曝光与白平衡统一、保边平滑、调色、少量色阶归并、描线、空气透视和抠天空。来源照片与许可见 Assets/Activities/CityPlaces-v2/selected-photos.json。

用法（仓库根目录，需要 torch、transformers、opencv、Pillow）：
  HF_HOME=build/agent-tmp/hf python3 Tools/ContentPipeline/stylize-place-scenes.py [地点 ID ...]
  --out <目录> 改输出位置（默认 App/Resources/StylizedPlaces），--preview <目录> 另存合成预览。
"""
import argparse
import json
import os
import sys

import cv2
import numpy as np
import torch
from PIL import Image
from transformers import (DPTForDepthEstimation, DPTImageProcessor, SegformerForSemanticSegmentation,
                          SegformerImageProcessor)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CATALOG = os.path.join(ROOT, "Assets/Activities/CityPlaces-v2/catalog.json")
FRAMING = os.path.join(ROOT, "App/Resources/activity-photo-framing.json")
SOURCE = os.path.join(ROOT, "App/Resources/ActivityPlacesGallery/scene-{}-v2.jpg")
MODEL = "nvidia/segformer-b5-finetuned-ade-640-640"
DEPTH_MODEL = "Intel/dpt-hybrid-midas"

# 竖版输出：比手机屏幕略宽，App 里铺满时留一点缓慢平移的余量。
OUT_W, OUT_H = 1242, 2548
MOTION_W, MOTION_H = 310, 637

SKY = [2]
FOLIAGE = {4: 1.0, 17: 1.0, 72: 1.0, 66: 0.6, 9: 0.25}
WATER = {21: 1.0, 26: 1.0, 60: 1.0, 128: 1.0, 109: 0.8, 113: 0.8, 104: 0.6}
INK = np.array([0.18, 0.2, 0.31], dtype=np.float32)
HAZE = np.array([0.9, 0.95, 1.0], dtype=np.float32)
# 风格强度：保边平滑、色阶数与混合比例、饱和度、描线浓度。
STYLE = {"passes": 3, "color_sigma": 34, "sigma_s": 30, "sigma_r": 0.25, "colors": 40, "poster": 0.3,
         "chroma": 1.2, "lines": 0.5}


def framing_fraction(place_id, framing):
    value = framing.get(f"scene-{place_id}-v2.jpg", "center")
    named = {"leading": 0.0, "trailing": 1.0, "center": 0.5}
    return named[value] if value in named else float(value)


def load_crop(place_id, framing):
    image = Image.open(SOURCE.format(place_id)).convert("RGB")
    width, height = image.size
    aspect = OUT_W / OUT_H
    if width / height > aspect:
        crop_w = round(height * aspect)
        x0 = round((width - crop_w) * framing_fraction(place_id, framing))
        box = (x0, 0, x0 + crop_w, height)
    else:
        crop_h = round(width / aspect)
        y0 = round((height - crop_h) * 0.5)
        box = (0, y0, width, y0 + crop_h)
    image = image.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS)
    return np.asarray(image).astype(np.float32) / 255


class Analyzer:
    """语义分割与单目深度，只输出需要的几张低分辨率图再放大，控制内存。"""

    def __init__(self):
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.seg_processor = SegformerImageProcessor.from_pretrained(MODEL)
        self.seg_model = SegformerForSemanticSegmentation.from_pretrained(MODEL).eval().to(self.device)
        self.depth_processor = DPTImageProcessor.from_pretrained(DEPTH_MODEL)
        self.depth_model = DPTForDepthEstimation.from_pretrained(DEPTH_MODEL).eval().to(self.device)

    def groups(self, rgb):
        image = (rgb * 255).astype(np.uint8)
        inputs = self.seg_processor(images=image, size={"height": 1280, "width": 640}, return_tensors="pt")
        with torch.no_grad():
            logits = self.seg_model(pixel_values=inputs["pixel_values"].to(self.device)).logits
            probs = torch.softmax(logits, dim=1)[0].float().cpu().numpy()
        del logits

        def group(weights):
            return sum(probs[k] * w for k, w in weights.items()).astype(np.float32)

        maps = [group({k: 1.0 for k in SKY}), group(FOLIAGE), group(WATER)]
        del probs
        depth = self.depth(image)
        if self.device == "mps":
            torch.mps.empty_cache()
        up = [cv2.resize(m, (OUT_W, OUT_H), interpolation=cv2.INTER_LINEAR) for m in maps]
        return up[0], up[1], up[2], depth

    def depth(self, image):
        """竖图分三块正方形估深度（模型只收正方形），按重叠区对齐尺度和偏移后拼起来。"""
        height, width = image.shape[:2]
        starts = [0, (height - width) // 2, height - width]
        tiles = []
        for y in starts:
            inputs = self.depth_processor(images=image[y:y + width], size={"height": 384, "width": 384},
                                          keep_aspect_ratio=False, return_tensors="pt")
            with torch.no_grad():
                predicted = self.depth_model(pixel_values=inputs["pixel_values"].to(self.device)).predicted_depth[0]
            tiles.append(cv2.resize(predicted.float().cpu().numpy(), (width, width), interpolation=cv2.INTER_CUBIC))
        for index in range(1, len(tiles)):
            offset = starts[index] - starts[index - 1]
            previous = tiles[index - 1][offset:].ravel()
            current = tiles[index][:width - offset].ravel()
            scale, shift = np.polyfit(current, previous, 1)
            tiles[index] = tiles[index] * scale + shift
        total = np.zeros((height, width), np.float32)
        weight = np.zeros((height, width), np.float32)
        ramp = np.minimum(np.arange(width) + 1, width - np.arange(width)).astype(np.float32)[:, None]
        for y, tile in zip(starts, tiles):
            total[y:y + width] += tile * ramp
            weight[y:y + width] += ramp
        return total / weight


def box(image, radius):
    return cv2.boxFilter(image, -1, (2 * radius + 1, 2 * radius + 1))


def guided_filter(guide, source, radius, eps):
    """灰度引导滤波：让分割概率、深度贴到照片里真实的边缘上。"""
    mean_i, mean_p = box(guide, radius), box(source, radius)
    cov = box(guide * source, radius) - mean_i * mean_p
    var = box(guide * guide, radius) - mean_i * mean_i
    a = cov / (var + eps)
    b = mean_p - a * mean_i
    return box(a, radius) * guide + box(b, radius)


def sky_matte(rgb, sky, foliage, depth):
    """天空遮罩：主体按分割结果二值化并清掉碎块，只在边界几像素内按照片边缘做软过渡。"""
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    hard = (sky > 0.5).astype(np.uint8)
    if hard.mean() > 0.005:
        # 悬在天空里、不接地面的小块“前景”（原照片的云团、噪点）并入天空。
        count, labels, stats, _ = cv2.connectedComponentsWithStats((hard == 0).astype(np.uint8), 8)
        bottom = stats[:, cv2.CC_STAT_TOP] + stats[:, cv2.CC_STAT_HEIGHT] >= OUT_H - 2
        large = stats[:, cv2.CC_STAT_AREA] > OUT_W * OUT_H * 0.05
        floating = np.where(~bottom & ~large)[0]
        floating = floating[floating != 0]
        if len(floating):
            hard[np.isin(labels, floating)] = 1
        # 地面上零星的“天空”小块去掉。
        count, labels, stats, _ = cv2.connectedComponentsWithStats(hard, 8)
        small = np.where(stats[:, cv2.CC_STAT_AREA] < 400)[0]
        small = small[small != 0]
        if len(small):
            hard[np.isin(labels, small)] = 0
    confident = (sky > 0.92) & (hard == 1)
    if confident.sum() > 2000:
        # 树冠、栏杆缝隙里的小块天空：在靠近天空的树叶处按天空颜色补抠。
        lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)
        samples = lab[confident][::7]
        mean = samples.mean(0)
        inv = np.linalg.inv(np.cov(samples.T) + np.eye(3) * 4).astype(np.float32)
        diff = (lab - mean).astype(np.float32)
        likeness = np.exp(-(diff @ inv * diff).sum(-1) / 6)
        near_sky = cv2.dilate(confident.astype(np.uint8), np.ones((61, 61), np.uint8)) > 0
        holes = (likeness > 0.5) & near_sky & (foliage > 0.3)
        # 原照片里贴着树冠或楼顶的云：颜色像天空、和天空一样远、分割也有几分像天空，
        # 且与天空连成一片，归入天空。远处楼群的深度明显更近，不受影响。
        sky_depth = float(np.median(depth[confident]))
        clouds = (likeness > 0.35) & (sky > 0.12) & (depth < sky_depth * 1.5) & (foliage < 0.3)
        # 只认成团的云：开运算去掉沿楼边、栏杆顶的细条（细物体的深度会被抹向远处）。
        clouds = cv2.morphologyEx(clouds.astype(np.uint8), cv2.MORPH_OPEN,
                                  cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (13, 13))) > 0
        merged = np.maximum(hard, clouds.astype(np.uint8))
        count, labels = cv2.connectedComponents(merged, connectivity=8)
        clouds &= np.isin(labels, np.unique(labels[confident]))
        # 单目深度在树冠边缘会被抹开，云块贴着树的那一条可能显得比天空近：只在已认定的大块云周围，
        # 把颜色非常像天空、又不是树叶的像素一并归入。细碎的判定（如远楼边缘）不作种子。
        count, labels, stats, _ = cv2.connectedComponentsWithStats(clouds.astype(np.uint8), 8)
        seeds = np.where(stats[:, cv2.CC_STAT_AREA] > 1500)[0]
        seeds = seeds[seeds != 0]
        if len(seeds):
            around = cv2.dilate(np.isin(labels, seeds).astype(np.uint8), np.ones((41, 41), np.uint8)) > 0
            clouds |= around & (likeness > 0.6) & (sky > 0.05) & (foliage < 0.3)
        hard = np.maximum(hard, (holes | clouds).astype(np.uint8))
    soft = np.clip(guided_filter(gray, hard.astype(np.float32), 4, 1e-3), 0, 1)
    band = cv2.dilate(hard, np.ones((7, 7), np.uint8)) - cv2.erode(hard, np.ones((7, 7), np.uint8))
    matte = np.where(band > 0, soft, hard.astype(np.float32))
    matte = cv2.GaussianBlur(matte, (0, 0), 0.7)
    matte[matte < 0.05] = 0
    matte[matte > 0.95] = 1
    return matte


def nearness(depth, gray, alpha):
    """把相对深度换成 0（远）到 1（近），贴合边缘并抹平，天空记为最远。"""
    foreground = alpha > 0.5
    values = depth[foreground] if foreground.sum() > 1000 else depth.ravel()
    low, high = np.percentile(values, 3), np.percentile(values, 97)
    near = np.clip((depth - low) / max(high - low, 1e-3), 0, 1).astype(np.float32)
    near = np.clip(guided_filter(gray, near, 8, 1e-3), 0, 1) * alpha
    return cv2.GaussianBlur(near, (0, 0), 3)


def decontaminate(rgb, sky_alpha):
    """半透明边缘去掉原天空的灰白色，换上背后新天空时不起白边。"""
    weight = (sky_alpha > 0.9).astype(np.float32)
    blurred = cv2.GaussianBlur(rgb * weight[..., None], (0, 0), 25)
    norm = cv2.GaussianBlur(weight, (0, 0), 25)[..., None]
    background = np.where(norm > 1e-3, blurred / np.maximum(norm, 1e-3), rgb)
    fg_alpha = (1 - sky_alpha)[..., None]
    edge = (fg_alpha > 0.02) & (fg_alpha < 0.98)
    fixed = (rgb - (1 - fg_alpha) * background) / np.maximum(fg_alpha, 0.05)
    return np.where(edge, np.clip(fixed, 0, 1), rgb).astype(np.float32)


def normalize(rgb, alpha):
    """统一曝光和白平衡：阴天、暗巷、偏色的照片拉到同一档明亮通透的基线。"""
    lab = cv2.cvtColor(rgb, cv2.COLOR_RGB2LAB)
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    mask = alpha > 0.5
    values = L[mask] if mask.sum() > 1000 else L.ravel()
    p2, p50, p98 = np.percentile(values, [2, 50, 98])
    t = np.clip((L - p2) / max(p98 - p2, 5), 0, 1)
    median = np.clip((p50 - p2) / max(p98 - p2, 5), 0.05, 0.95)
    gamma = float(np.clip(np.log(0.56) / np.log(median), 0.6, 1.25))
    L = (5 + 89 * t ** gamma)
    mid = mask & (t > 0.2) & (t < 0.85)
    if mid.sum() > 1000:
        a = a - 0.55 * a[mid].mean()
        b = b - 0.45 * b[mid].mean()
    return cv2.cvtColor(np.stack([L, a, b], -1).astype(np.float32), cv2.COLOR_LAB2RGB)


def posterize(lab, colors):
    small = cv2.resize(lab, (OUT_W // 4, OUT_H // 4), interpolation=cv2.INTER_AREA).reshape(-1, 3)
    criteria = (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 20, 1.0)
    cv2.setRNGSeed(7)
    _, _, centers = cv2.kmeans(small, colors, None, criteria, 2, cv2.KMEANS_PP_CENTERS)
    flat = lab.reshape(-1, 3)
    out = np.empty_like(flat)
    for start in range(0, len(flat), 200_000):
        chunk = flat[start:start + 200_000]
        nearest = np.argmin(((chunk[:, None, :] - centers[None]) ** 2).sum(-1), axis=1)
        out[start:start + 200_000] = centers[nearest]
    return out.reshape(lab.shape)


def stylize(rgb, foliage, water, near, has_sky):
    image8 = (np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    # 1. 保边平滑：多遍双边滤波抹掉噪点和细碎纹理，墙面、路面成为干净的色面，结构线保留。
    smooth = image8
    for _ in range(STYLE["passes"]):
        smooth = cv2.bilateralFilter(smooth, 9, STYLE["color_sigma"], 7)
    smooth = cv2.edgePreservingFilter(smooth, flags=cv2.NORMCONV_FILTER, sigma_s=STYLE["sigma_s"], sigma_r=STYLE["sigma_r"])
    # 2. 色阶归并：少量色块让画面像手绘上色，再与平滑结果混合保留渐变；中值滤波去掉孤立的色点。
    lab = cv2.cvtColor(smooth.astype(np.float32) / 255, cv2.COLOR_RGB2LAB)
    poster = cv2.medianBlur(posterize(lab, STYLE["colors"]), 5)
    poster = cv2.GaussianBlur(poster, (0, 0), 1.0)
    lab = lab * (1 - STYLE["poster"]) + poster * STYLE["poster"]
    # 3. 插画调色：提饱和（灰的颜色多提一些），暗部偏蓝紫，亮部偏暖。
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    chroma = np.sqrt(a * a + b * b)
    boost = STYLE["chroma"] + 0.35 * np.exp(-chroma / 18)
    shadow = np.clip((50 - L) / 40, 0, 1)
    highlight = np.clip((L - 70) / 30, 0, 1)
    L = 8 + L * 0.9
    a = a * boost + shadow * 3
    b = b * boost - shadow * 8 + highlight * 5
    graded = np.clip(cv2.cvtColor(np.stack([L, a, b], -1), cv2.COLOR_LAB2RGB), 0, 1)
    # 4. 空气透视：有天空的室外场景，远处融进天色，近处保持清楚。
    if has_sky:
        far = (np.clip((0.45 - near) / 0.45, 0, 1) ** 2)[..., None] * 0.18
        graded = graded * (1 - far) + HAZE * far
    # 5. 细描线（XDoG）：只描真正的边，去掉孤立小点；树叶和水面上减弱，避免一片乱线。
    gray = cv2.cvtColor(smooth, cv2.COLOR_RGB2GRAY).astype(np.float32) / 255
    dog = cv2.GaussianBlur(gray, (0, 0), 1.0) - 0.985 * cv2.GaussianBlur(gray, (0, 0), 1.8)
    lines = np.clip(1 - (1 + np.tanh(70 * (dog + 0.012))), 0, 1)
    gx = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    gy = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    lines *= np.clip((np.sqrt(gx * gx + gy * gy) - 0.08) / 0.12, 0, 1)
    count, labels, stats, _ = cv2.connectedComponentsWithStats((lines > 0.25).astype(np.uint8), 8)
    tiny = np.where(stats[:, cv2.CC_STAT_AREA] < 14)[0]
    lines[np.isin(labels, tiny[tiny != 0])] = 0
    lines = cv2.GaussianBlur(lines, (0, 0), 0.6)
    lines *= 1 - 0.65 * np.clip(foliage, 0, 1) - 0.5 * np.clip(water, 0, 1)
    lines *= 0.55 + 0.45 * near
    lines = np.clip(lines, 0, 1)[..., None] * STYLE["lines"]
    styled = graded * (1 - lines) + INK * lines
    # 6. 柔光：亮处轻微晕开，画面更通透。
    bright = np.clip((styled - 0.72) / 0.28, 0, 1)
    styled = 1 - (1 - styled) * (1 - cv2.GaussianBlur(bright, (0, 0), 14) * 0.22)
    # 7. 轻微锐化，保住细节。
    soft = cv2.GaussianBlur(styled, (0, 0), 1.2)
    return np.clip(styled + (styled - soft) * 0.45, 0, 1).astype(np.float32)


def preview_sky(height, width):
    top, bottom = np.array([0.75, 0.89, 1.0]), np.array([0.96, 0.98, 1.0])
    t = np.linspace(0, 1, height)[:, None, None]
    return np.broadcast_to(top * (1 - t) + bottom * t, (height, width, 3))


def process(place_id, analyzer, framing, out_dir, preview_dir):
    rgb = load_crop(place_id, framing)
    sky, foliage, water, depth = analyzer.groups(rgb)
    sky_alpha = sky_matte(rgb, sky, foliage, depth)
    has_sky = sky_alpha.mean() > 0.01
    if has_sky:
        rgb = decontaminate(rgb, sky_alpha)
    else:
        sky_alpha[:] = 0
    alpha = (1 - sky_alpha).astype(np.float32)
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    near = nearness(depth, gray, alpha)
    styled = stylize(normalize(rgb, alpha), foliage, water, near, has_sky)
    rgba = np.concatenate([styled, alpha[..., None]], -1)
    os.makedirs(out_dir, exist_ok=True)
    Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").save(
        os.path.join(out_dir, f"styled-place-{place_id}.webp"), quality=84, method=6)
    motion = np.stack([np.clip(foliage, 0, 1) * alpha, np.clip(water, 0, 1) * alpha, near], -1)
    motion = cv2.GaussianBlur(cv2.resize(motion, (MOTION_W, MOTION_H), interpolation=cv2.INTER_AREA), (0, 0), 1.2)
    Image.fromarray((np.clip(motion, 0, 1) * 255).astype(np.uint8), "RGB").save(
        os.path.join(out_dir, f"styled-place-{place_id}-motion.png"), optimize=True)
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        composite = styled * alpha[..., None] + preview_sky(OUT_H, OUT_W) * (1 - alpha[..., None])
        Image.fromarray((composite * 255).astype(np.uint8)).save(os.path.join(preview_dir, f"{place_id}.jpg"), quality=88)
    return {"id": place_id, "sky": round(float(sky_alpha.mean()), 3), "foliage": round(float((foliage * alpha).mean()), 3),
            "water": round(float((water * alpha).mean()), 3)}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("ids", nargs="*")
    parser.add_argument("--out", default=os.path.join(ROOT, "App/Resources/StylizedPlaces"))
    parser.add_argument("--preview")
    parser.add_argument("--style", help="覆盖风格参数的 JSON，用于比较")
    args = parser.parse_args()
    places = [p["id"] for p in json.load(open(CATALOG))["places"]]
    ids = args.ids or places
    framing = json.load(open(FRAMING))
    if args.style:
        STYLE.update(json.loads(args.style))
    analyzer = Analyzer()
    report = []
    for place_id in ids:
        report.append(process(place_id, analyzer, framing, args.out, args.preview))
        print(json.dumps(report[-1], ensure_ascii=False), flush=True)
    return report


if __name__ == "__main__":
    sys.exit(0 if main() else 1)
