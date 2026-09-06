#!/usr/bin/env bash
# Deterministic finishing only. Source: licensed Mixkit 4169; no synthetic people.
set -euo pipefail
cafe_source="${1:?Pass Mixkit 4169 source mp4}"
cafe_master="${2:-Assets/Activities/Cafe/interior-source.png}"
cafe_output="App/Resources/ActivityScene"
mkdir -p "$cafe_output"
ffmpeg -v error -y -i "$cafe_master" -vf 'scale=852:1847:flags=lanczos' -frames:v 1 -q:v 2 "$cafe_output/activity-cafe-interior.jpg"
# Fixed view and colour conversion shared by all clips and the resting plate.
ffmpeg -v error -y -ss 5.2 -i "$cafe_source" -vf 'crop=900:720:190:0,scale=650:520:flags=lanczos,setsar=1' \
  -frames:v 1 -q:v 2 "$cafe_output/activity-cafe-window.jpg"
make_event() {
  local event_id="$1" start="$2" duration="$3" fade_out="$4"
  ffmpeg -v error -y -loop 1 -framerate 25 -i "$cafe_output/activity-cafe-window.jpg" \
    -ss "$start" -t "$duration" -i "$cafe_source" -filter_complex \
    "[1:v]setpts=PTS-STARTPTS,crop=900:720:190:0,scale=650:520:flags=lanczos,setsar=1,format=yuva420p,fade=t=in:st=0:d=0.16:alpha=1,fade=t=out:st=$fade_out:d=0.16:alpha=1[event];[0:v][event]overlay=shortest=1:format=auto,format=yuv420p[out]" \
    -map '[out]' -t "$duration" -an -c:v libx264 -preset slow -crf 19 -movflags +faststart \
    "$cafe_output/activity-cafe-event-$event_id.mp4"
}
# Boundaries are empty of foreground walkers in this crop. Brief blends reconcile
# distant exposure/background only, never a foreground body. No reverse/timewarp.
make_event 0 2.4 2.6 2.4
make_event 1 5.08 8.32 8.12
make_event 2 14.0 3.8 3.6
