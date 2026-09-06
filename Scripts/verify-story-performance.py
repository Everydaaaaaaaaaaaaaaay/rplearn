#!/usr/bin/env python3
"""Independent full-track recognition and measured loudness (local only).
uv run --with faster-whisper python Scripts/verify-story-performance.py OUTPUT --model small.en
"""
import argparse
import json
import re
import subprocess
from pathlib import Path
from faster_whisper import WhisperModel

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('output', type=Path)
parser.add_argument('--model', default='small.en')
args = parser.parse_args()
p = args.output
model = WhisperModel(args.model, device='cpu', compute_type='int8')
plan = json.loads((p/'performance-plan.json').read_text())
expected = ' '.join(item['text'] for item in plan['segments'])


def words(text):
    return re.findall(r"[a-z]+(?:'[a-z]+)?", text.lower().replace('’', "'"))


report = {'recognizer': args.model, 'results': {}}
for name in ['performance-dry', 'performance-room', 'original-matched']:
    segments, _ = model.transcribe(str(p/f'{name}.wav'), language='en', beam_size=5,
                                   condition_on_previous_text=False)
    recognized = ' '.join(segment.text.strip() for segment in segments)
    probe = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(p/f'{name}.wav'), '-af',
                            'loudnorm=I=-22:TP=-2:LRA=11:print_format=json', '-f', 'null', '-'],
                           capture_output=True, text=True, check=True)
    loudness, _ = json.JSONDecoder().raw_decode(probe.stderr[probe.stderr.rfind('{'):])
    result = dict(recognized=recognized, wordExact=words(recognized)==words(expected),
                  recognizedWords=len(words(recognized)), expectedWords=len(words(expected)),
                  measuredLUFS=float(loudness["input_i"]), truePeakDBFS=float(loudness["input_tp"]),
                  loudnessRangeLU=float(loudness["input_lra"]))
    report['results'][name] = result
    print(name, json.dumps(result, ensure_ascii=False), flush=True)
(p/'independent-final-check.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
# A mismatch is a listening/review candidate, never silent certification. Exit
# nonzero so explicit verification callers cannot confuse it with exact agreement.
if not all(report['results'][name]['wordExact'] for name in ['performance-dry', 'performance-room']):
    raise SystemExit('Final-track ASR discrepancy: review independent-final-check.json; not proof of a synthesis error.')
