#!/usr/bin/env bash
# Licensed Pexels 33741230; deterministic crop and forward-only loop finishing.
# Usage: bash Scripts/prepare-raincafe-activity-scene.sh source.mp4
set -euo pipefail

rain_source="${1:?Pass the licensed Pexels 33741230 source video}"
rain_output="App/Resources/ActivityScene"
mkdir -p "$rain_output"

# Keep the fixed vertical camera and native timing. The full first frame is the
# base; the upper window region remains live for the whole 17.5-second loop.
# Moving pedestrians and vehicles in the lower panes are deliberately excluded:
# full-frame blending made them double-exposed during review.
ffmpeg -v error -y -i "$rain_source" -filter_complex \
  "[0:v]crop=1181:2560:0:0,scale=852:1848:flags=lanczos,fps=24,setsar=1,split=3[still][a][b];[still]trim=start_frame=48:end_frame=49,loop=loop=-1:size=1:start=0,setpts=N/24/TB[base];[a]trim=start=2:end=19.5,setpts=PTS-STARTPTS[body];[b]trim=start=0:end=2,setpts=PTS-STARTPTS[head];[body][head]xfade=transition=fade:duration=2:offset=15.5[motion];[motion]crop=852:800:0:0,format=yuva420p,geq=lum='lum(X,Y)':cb='cb(X,Y)':cr='cr(X,Y)':a='255*min(1,(H-1-Y)/32)'[window];[base][window]overlay=0:0:shortest=1,format=yuv420p[out]" \
  -map '[out]' -an -t 17.5 -c:v libx264 -preset slow -crf 21 -movflags +faststart \
  "$rain_output/activity-raincafe-loop.mp4"

# The poster comes from the finished video so static/dynamic framing and colour
# agree. The one-pixel canvas crop happens identically in the app renderer.
ffmpeg -v error -y -i "$rain_output/activity-raincafe-loop.mp4" -frames:v 1 -q:v 2 \
  "$rain_output/activity-raincafe-poster.jpg"
