#!/usr/bin/env bash
# Reproduce the rejected café composite for diagnosis, never for release.
set -euo pipefail
if [[ "${1:-}" != "--rejected-preview" ]]; then
  echo 'Rejected recipe: pass --rejected-preview SOURCE PREVIEW_DIR for diagnostic reproduction only.' >&2
  exit 2
fi
shift
cafe_source="${1:?Pass stabilized 47-second intermediate from stabilize-cafe-footage.py}"
cafe_output="${2:?Pass a separate preview directory, not App/Resources}"
python3 "$(dirname "$0")/scene_preview_guard.py" --rejected-preview "$cafe_output"
mkdir -p "$cafe_output"
# The v2 interior is a separate one-shot master; never re-edit the old photograph.
# Historical rejected recipe: source eye height is incompatible with the café,
# and the whole-frame dissolve can ghost people. Adjacent file-boundary frames
# do not make that internal dissolve natural. Retained for comparisons only.
cafe_filter='crop=650:404:0:116,fps=24,setsar=1,eq=brightness=-0.035:saturation=0.85'
ffmpeg -v error -y -t 47 -i "$cafe_source" \
  -t 0.5 -i "$cafe_source" -filter_complex \
  "[0:v]setpts=PTS-STARTPTS,$cafe_filter[a];[1:v]setpts=PTS-STARTPTS,$cafe_filter[b];[a][b]xfade=transition=fade:duration=0.5:offset=46.5,trim=start=0.5,setpts=PTS-STARTPTS,format=yuv420p[out]" \
  -map '[out]' -an -c:v libx264 -preset slow -crf 19 -g 48 -movflags +faststart \
  "$cafe_output/activity-cafe-street-loop.mp4"
ffmpeg -v error -y -i "$cafe_output/activity-cafe-street-loop.mp4" \
  -frames:v 1 -q:v 2 "$cafe_output/activity-cafe-window.jpg"
echo 'REJECTED PREVIEW generated. Encoding success is not visual acceptance; do not ship.'
