#!/usr/bin/env python3
"""Rebuild the 15-second candidate from verified source files (ffmpeg required)."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--sources', type=Path, required=True, help='Directory containing sourceFile entries from candidates-v5.json')
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
rows = json.loads(Path(__file__).with_name('candidates-v5.json').read_text())
args.output.mkdir(parents=True, exist_ok=True)
clips = []
for row in rows:
    source = args.sources / row['sourceFile']
    digest = hashlib.sha256()
    with source.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != row['sourceSHA256']:
        raise ValueError(f"Source hash mismatch: {row['city']}")
    clip = (args.output / (row['city'] + '.mp4')).resolve()
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source),
                    '-map', '0:v:0', '-vf', row['filter'], '-an', '-c:v', 'libx264',
                    '-preset', 'fast', '-crf', '20', '-pix_fmt', 'yuv420p',
                    '-enc_time_base', '1:60', '-fps_mode', 'passthrough',
                    '-g', '60', '-keyint_min', '60', '-sc_threshold', '0',
                    '-map_metadata', '-1', '-write_tmcd', '0', '-movflags', '+faststart', str(clip)], check=True)
    clips.append(clip)
concat = args.output / 'concat.txt'
# ffmpeg concat files use their own quoting, not shell quoting.
concat.write_text(''.join("file '" + str(p).replace("'", "'\\''") + "'\n" for p in clips))
subprocess.run(['ffmpeg', '-v', 'error', '-y', '-f', 'concat', '-safe', '0', '-i', str(concat),
                '-map', '0:v:0', '-c', 'copy', '-map_metadata', '-1', '-write_tmcd', '0',
                '-movflags', '+faststart', str(args.output / 'encounter-journey.mp4')], check=True)
