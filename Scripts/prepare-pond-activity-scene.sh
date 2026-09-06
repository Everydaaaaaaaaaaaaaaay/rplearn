#!/usr/bin/env bash
# Licensed Mixkit 1202, one-shot foreground; deterministic finishing only.
# Usage: bash Scripts/prepare-pond-activity-scene.sh source.mp4 foreground.png
set -euo pipefail
pond_source="${1:?Pass Mixkit 1202 source video}"
pond_foreground="${2:?Pass the immutable foreground master}"
pond_output="App/Resources/ActivityScene"
mkdir -p "$pond_output"
ffmpeg -v error -y -i "$pond_foreground" -vf 'crop=852:999:0:848' \
  -q:v 2 -frames:v 1 "$pond_output/activity-pond-table.jpg"
# Upper crop excludes the fish and edge throughout. Only water/reflections
# blend, in forward time: source 18..20 into 0..2, after starting at 2s.
# The encoded file boundary is therefore two adjacent source frames.
ffmpeg -v error -y -i "$pond_source" -filter_complex \
  '[0:v]fps=24,trim=duration=20,crop=584:584:68:0,setsar=1,split[a][b];[a]trim=start=2,setpts=PTS-STARTPTS[tail];[b]trim=end=2,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=2:offset=16,format=yuv420p[out]' \
  -map '[out]' -an -t 18 -c:v libx264 -preset slow -crf 22 -movflags +faststart \
  "$pond_output/activity-pond-loop.mp4"
ffmpeg -v error -y -i "$pond_output/activity-pond-loop.mp4" -frames:v 1 -q:v 2 \
  "$pond_output/activity-pond-poster.jpg"
