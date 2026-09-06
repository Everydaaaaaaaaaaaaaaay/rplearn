#!/usr/bin/env bash
# Deterministic, non-generative finishing of the one-shot foreground and stock clip.
# Usage: bash Scripts/prepare-activity-scene.sh <Mixkit-4831.mp4> <foreground.png>
set -euo pipefail
activity_source="${1:?Pass the licensed Mixkit 4831 source video}"
activity_foreground="${2:?Pass the one-shot foreground image}"
activity_output="App/Resources/ActivityScene"
mkdir -p "$activity_output"
# The image generator returned RGB checkerboard, not alpha. Only the fully opaque
# rectangular table is used: crop without any regeneration or material changes.
ffmpeg -v error -y -i "$activity_foreground" -vf 'crop=852:789:0:1058' \
  -q:v 2 -frames:v 1 "$activity_output/activity-table.jpg"
# No actor crossfade and no reverse playback. Fade only while the cropped path is
# empty; preserve the complete runner including her head and feet. The feathered
# strip edge is clear of her silhouette. Everything outside the strip is frame 0.
ffmpeg -v error -y -i "$activity_source" -filter_complex \
  "[0:v]fps=24,trim=duration=8,split[b][m];[b]trim=end_frame=1,loop=loop=-1:size=1:start=0,setpts=N/24/TB[base];[m]crop=1280:350:0:180,format=yuva420p,geq=lum='lum(X,Y)':cb='cb(X,Y)':cr='cr(X,Y)':a='255*min(1,min(Y/16,(H-1-Y)/16))',fade=t=in:st=0:d=0.5:alpha=1,fade=t=out:st=7.3:d=0.5:alpha=1[strip];[base][strip]overlay=0:180:shortest=1,crop=554:720:360:0,scale=852:1108:flags=lanczos,setsar=1[out]" \
  -map '[out]' -an -t 8 -c:v libx264 -preset slow -crf 19 -pix_fmt yuv420p \
  -movflags +faststart "$activity_output/activity-park-loop.mp4"
ffmpeg -v error -y -i "$activity_output/activity-park-loop.mp4" \
  -frames:v 1 -q:v 2 "$activity_output/activity-park-poster.jpg"
