#!/usr/bin/env bash
# Explicit local audio audition; no server, paid provider, deployment or phone install.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
audition_output="${1:-build/verification/story-speech-$(date -u '+%Y%m%dT%H%M%SZ')}"
mkdir -p "$audition_output"
audition_output="$(cd "$audition_output" && pwd)"
Scripts/test.sh -only-testing:LingoTripTests/SpeechDeliveryAuditionTests \
  RUN_SPEECH_SAMPLE=1 -resultBundlePath "$audition_output/run.xcresult"
python3 Scripts/export-story-speech.py "$audition_output/run.xcresult" "$audition_output"
printf '试听文件：%s\n' "$audition_output"
