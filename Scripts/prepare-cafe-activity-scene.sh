#!/usr/bin/env bash
# Deterministic finishing only; Pixabay 27023 / Davide Giordani.
set -euo pipefail
cafe_source="${1:?Pass stabilized 47-second intermediate from stabilize-cafe-footage.py}"
cafe_output="${2:-App/Resources/ActivityScene}"
mkdir -p "$cafe_output"
# The v2 interior is a separate one-shot master; never re-edit the old photograph.
# 13.5–60.5: several complete distinct pedestrian passes, no foreground body at
# the join. Fixed crop, natural speed. Reconcile distant movement/exposure over
# 12 frames; rotate the finished seam to the end, then loop on consecutive frames.
cafe_filter='crop=650:404:0:116,fps=24,setsar=1,eq=brightness=-0.035:saturation=0.85'
ffmpeg -v error -y -t 47 -i "$cafe_source" \
  -t 0.5 -i "$cafe_source" -filter_complex \
  "[0:v]setpts=PTS-STARTPTS,$cafe_filter[a];[1:v]setpts=PTS-STARTPTS,$cafe_filter[b];[a][b]xfade=transition=fade:duration=0.5:offset=46.5,trim=start=0.5,setpts=PTS-STARTPTS,format=yuv420p[out]" \
  -map '[out]' -an -c:v libx264 -preset slow -crf 19 -g 48 -movflags +faststart \
  "$cafe_output/activity-cafe-street-loop.mp4"
ffmpeg -v error -y -i "$cafe_output/activity-cafe-street-loop.mp4" \
  -frames:v 1 -q:v 2 "$cafe_output/activity-cafe-window.jpg"
