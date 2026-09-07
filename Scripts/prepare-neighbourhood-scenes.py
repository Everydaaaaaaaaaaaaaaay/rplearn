#!/usr/bin/env python3
"""Register licensed footage to a fixed facade, crop, grade and close the seam.

Usage: python prepare-neighbourhood-scenes.py bookstall|flowerstall SOURCE OUTPUT_DIR
Requires opencv-python-headless, numpy and ffmpeg. No generative image processing.
Masters/provenance: Assets/Activities/StreetStalls/README.md.
"""
import pathlib
import subprocess
import sys
import tempfile

import cv2
import numpy as np

scene, source, output = sys.argv[1:]
config = {
    "bookstall": dict(source=(3840, 2160), start=14.0, seconds=45.5, crop=(1700, 0, 1560, 2150),
                     size=(1024, 1412), mask=(0, 25, 720, 170), name="street", saturation=0.9),
    "flowerstall": dict(source=(1920, 1080), start=0.5, seconds=62.0, crop=(820, 0, 750, 1080),
                   size=(750, 1080), mask=(0, 5, 720, 160), name="street", saturation=0.9),
}[scene]
out = pathlib.Path(output)
out.mkdir(parents=True, exist_ok=True)
w, h = config["source"]
ow, oh = config["size"]
x, y, cw, ch = config["crop"]
resize = np.diag([720 / w, 405 / h, 1.0])
crop = np.array([[ow / cw, 0, -x * ow / cw], [0, oh / ch, -y * oh / ch], [0, 0, 1.0]])
mask = np.zeros((405, 720), dtype=np.uint8)
mx, my, mw, mh = config["mask"]
mask[my:my + mh, mx:mx + mw] = 255
sift = cv2.SIFT_create(nfeatures=2200)
matcher = cv2.BFMatcher()
count = 0
expected_frames = int(config["seconds"] * 24)
with tempfile.TemporaryDirectory(prefix="lingotrip-registered-") as scratch:
    intermediate = str(pathlib.Path(scratch) / "registered.mp4")
    decoder = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(config["start"]), "-t",
        str(config["seconds"]), "-i", source, "-vf", f"scale={w}:{h},fps=24", "-frames:v", str(expected_frames), "-f", "rawvideo", "-pix_fmt",
        "bgr24", "-"], stdout=subprocess.PIPE)
    encoder = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt",
        "bgr24", "-s", f"{ow}x{oh}", "-r", "24", "-i", "-", "-an", "-c:v", "libx264",
        "-preset", "fast", "-crf", "14", "-pix_fmt", "yuv420p", intermediate], stdin=subprocess.PIPE)
    reference_points = reference_features = None
    try:
        while raw := decoder.stdout.read(w * h * 3):
            if len(raw) != w * h * 3:
                raise RuntimeError("Truncated frame")
            frame = np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 3)
            small = cv2.cvtColor(cv2.resize(frame, (720, 405)), cv2.COLOR_BGR2GRAY)
            points, features = sift.detectAndCompute(small, mask)
            if reference_features is None:
                reference_points, reference_features = points, features
            matches = [a for a, b in matcher.knnMatch(features, reference_features, k=2)
                       if a.distance < 0.7 * b.distance]
            if len(matches) < 25:
                raise RuntimeError(f"Unstable architecture at frame {count}")
            src = np.float32([points[m.queryIdx].pt for m in matches])
            dst = np.float32([reference_points[m.trainIdx].pt for m in matches])
            transform, inliers = cv2.findHomography(src, dst, cv2.RANSAC, 1.5)
            if transform is None or int(inliers.sum()) < 16:
                raise RuntimeError(f"Insufficient inliers at frame {count}")
            transform = np.linalg.inv(resize) @ transform @ resize
            rendered = cv2.warpPerspective(frame, crop @ transform, (ow, oh), flags=cv2.INTER_LANCZOS4)
            encoder.stdin.write(rendered.tobytes())
            count += 1
    finally:
        decoder.stdout.close()
        encoder.stdin.close()
        decode_status, encode_status = decoder.wait(), encoder.wait()
    if decode_status or encode_status or count != expected_frames:
        raise RuntimeError(f"Incomplete registration: {count}, {decode_status}/{encode_status}")
    # The last 0.5 s transitions to the first 0.5 s. Start output at 0.5,
    # so the file boundary itself is adjacent source frames, never a seek gap.
    movie = out / f"activity-{scene}-{config['name']}-loop.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", intermediate, "-filter_complex",
        f"[0:v]eq=brightness=-0.025:saturation={config['saturation']},split[a][b];"
        f"[a][b]xfade=transition=fade:duration=0.5:offset={config['seconds'] - 0.5},"
        f"trim=start=0.5:end={config['seconds']},setpts=PTS-STARTPTS[v]",
        "-map", "[v]", "-an", "-c:v", "libx264", "-preset", "slow", "-crf", "19",
        "-pix_fmt", "yuv420p", "-g", "48", "-movflags", "+faststart", str(movie)], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(movie), "-frames:v", "1",
        "-q:v", "2", str(out / f"activity-{scene}-window.jpg")], check=True)
print(f"{scene}: registered {count} frames; {config['seconds'] - 0.5} s continuous silent loop")
