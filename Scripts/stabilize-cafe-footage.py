#!/usr/bin/env python3
"""Offline registration to one architectural reference, never AI repainting.

Requires opencv-python-headless and ffmpeg. Input is the licensed 27023 master;
output is a 47 s, 650x520 intermediate for prepare-cafe-activity-scene.sh.
"""
import subprocess
import sys

import cv2
import numpy as np

source, destination = sys.argv[1:]
decoder = subprocess.Popen([
    "ffmpeg", "-v", "error", "-ss", "13.5", "-t", "47", "-i", source,
    "-vf", "fps=24", "-f", "rawvideo", "-pix_fmt", "bgr24", "-",
], stdout=subprocess.PIPE)
encoder = subprocess.Popen([
    "ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24",
    "-s", "650x520", "-r", "24", "-i", "-", "-an", "-c:v", "libx264",
    "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p", destination,
], stdin=subprocess.PIPE)
sift = cv2.SIFT_create(nfeatures=1800)
matcher = cv2.BFMatcher()
mask = np.zeros((405, 720), dtype=np.uint8)
# Static building facades only: exclude walkers, flags and bright sky.
mask[30:280, 20:335] = 255
mask[155:275, 425:670] = 255
reference_points = reference_features = None
resize = np.diag([720 / 1920, 405 / 1080, 1.0])
window = np.array([[0.5, 0, -200], [0, 0.5, -20], [0, 0, 1.0]])
count = 0
try:
    while True:
        raw = decoder.stdout.read(1920 * 1080 * 3)
        if not raw:
            break
        if len(raw) != 1920 * 1080 * 3:
            raise RuntimeError("Incomplete source frame")
        frame = np.frombuffer(raw, dtype=np.uint8).reshape(1080, 1920, 3)
        small = cv2.cvtColor(cv2.resize(frame, (720, 405)), cv2.COLOR_BGR2GRAY)
        points, features = sift.detectAndCompute(small, mask)
        if reference_features is None:
            reference_points, reference_features = points, features
        pairs = matcher.knnMatch(features, reference_features, k=2)
        matches = [a for a, b in pairs if a.distance < 0.7 * b.distance]
        if len(matches) < 35:
            raise RuntimeError(f"Frame {count}: insufficient architectural matches")
        src = np.float32([points[m.queryIdx].pt for m in matches])
        dst = np.float32([reference_points[m.trainIdx].pt for m in matches])
        transform, inliers = cv2.findHomography(src, dst, cv2.RANSAC, 1.0)
        if transform is None or int(inliers.sum()) < 30:
            raise RuntimeError(f"Frame {count}: unstable registration")
        transform = np.linalg.inv(resize) @ transform @ resize
        rendered = cv2.warpPerspective(frame, window @ transform, (650, 520), flags=cv2.INTER_LANCZOS4)
        encoder.stdin.write(rendered.tobytes())
        count += 1
finally:
    decoder.stdout.close()
    encoder.stdin.close()
    decode_status, encode_status = decoder.wait(), encoder.wait()
if decode_status or encode_status or count != 1128:
    raise RuntimeError(f"Incomplete output: {count} frames, processes {decode_status}/{encode_status}")
print(f"Registered {count} frames; source timestamps preserved over 47 s. This does not validate natural gait or camera compatibility.")
