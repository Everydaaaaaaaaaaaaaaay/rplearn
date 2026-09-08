#!/usr/bin/env bash
# Deterministic, non-generative finishing of the one-shot foreground and stock clip.
# Usage: bash Scripts/prepare-activity-scene.sh <Mixkit-4831.mp4> <foreground.png>
set -euo pipefail
activity_source="${1:?Pass the licensed Mixkit 4831 source video}"
activity_foreground="${2:?Pass the one-shot foreground image}"
activity_output="App/Resources/ActivityScene"
activity_tmp="$(mktemp -d)"
trap 'rm -r "$activity_tmp"' EXIT
mkdir -p "$activity_output"
# The image generator returned RGB checkerboard, not alpha. Only the fully opaque
# rectangular table is used: crop without any regeneration or material changes.
ffmpeg -v error -y -i "$activity_foreground" -vf 'crop=852:789:0:1058' \
  -q:v 2 -frames:v 1 "$activity_output/activity-table.jpg"
# Preserve real environmental movement after the runner leaves. The no-person
# section is turned into a three-second forward loop: source 1.1...4.1 blends
# with source 0...1.1, ending on the same source moment at which the next cycle
# begins. This keeps the locked camera, leaves, grass and distant bridge traffic
# alive without manufacturing another person or reversing time.
ffmpeg -v error -y -i "$activity_source" -filter_complex \
  "[0:v]fps=24,crop=554:720:360:0,scale=852:1108:flags=lanczos,setsar=1,split[a][b];[a]trim=start=1.1:end=4.1,setpts=PTS-STARTPTS[tail];[b]trim=start=0:end=1.1,setpts=PTS-STARTPTS[head];[tail][head]xfade=transition=fade:duration=1.1:offset=1.9,format=yuv420p[out]" \
  -map '[out]' -an -t 3 -c:v libx264 -preset slow -crf 20 -movflags +faststart \
  "$activity_tmp/ambient.mp4"

# One real runner pass sits at the start of an 81-second continuous environment
# loop. It fades in while the path is empty and fades back only after the runner
# has left the frame, so the actor is never dissolved. At the 81-second boundary
# both sides use the same ambient layer. There is no freeze, reverse, speed
# change, duplicate actor or generated frame.
ffmpeg -v error -y -stream_loop 26 -i "$activity_tmp/ambient.mp4" -i "$activity_source" \
  -filter_complex \
  "[0:v]trim=duration=81,setpts=PTS-STARTPTS[base];[1:v]fps=24,trim=start=1.1:end=8.25,setpts=PTS-STARTPTS,crop=554:720:360:0,scale=852:1108:flags=lanczos,setsar=1,format=yuva420p,fade=t=in:st=0:d=0.8:alpha=1,fade=t=out:st=6.3:d=0.8:alpha=1[event];[base][event]overlay=0:0:eof_action=pass:shortest=0,format=yuv420p[out]" \
  -map '[out]' -an -t 81 -c:v libx264 -preset slow -crf 20 -movflags +faststart \
  "$activity_output/activity-park-loop.mp4"
ffmpeg -v error -y -i "$activity_output/activity-park-loop.mp4" \
  -frames:v 1 -q:v 2 "$activity_output/activity-park-poster.jpg"
