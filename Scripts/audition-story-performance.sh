#!/usr/bin/env bash
# Explicit, fully local production audition. First ASR use downloads model weights.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
performance_output="${1:-build/verification/story-performance-$(date -u '+%Y%m%dT%H%M%SZ')}"
mkdir -p "$performance_output"
performance_output="$(cd "$performance_output" && pwd)"
Scripts/test.sh -only-testing:LingoTripTests/StoryPerformanceCandidateTests \
  -only-testing:LingoTripTests/SpeechDeliveryAuditionTests RUN_SPEECH_SAMPLE=1 \
  -resultBundlePath "$performance_output/run.xcresult"
python3 Scripts/export-story-speech.py "$performance_output/run.xcresult" "$performance_output/baseline"
uv run --with faster-whisper python Scripts/master-story-speech.py "$performance_output" \
  --result "$performance_output/run.xcresult" --baseline "$performance_output/baseline/scene-original.wav"
printf '完整试听：%s/performance-dry.wav\n同步字幕：%s/index.html\n' "$performance_output" "$performance_output"
