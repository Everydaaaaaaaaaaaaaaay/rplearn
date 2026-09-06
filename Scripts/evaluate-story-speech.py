#!/usr/bin/env python3
"""Optional local ASR audit of exported audition WAVs; never a quality gate.

Run: uv run --with faster-whisper Scripts/evaluate-story-speech.py OUTPUT_DIRECTORY
First use downloads base.en weights; synthesis audio stays local.
"""
import argparse
import importlib.metadata
import json
import re
from pathlib import Path
from faster_whisper import WhisperModel


def words(text):
    return re.findall(r"[a-z]+(?:'[a-z]+)?", text.lower().replace("’", "'"))


def distance(a, b):
    row = list(range(len(b) + 1))
    for i, left in enumerate(a, 1):
        next_row = [i]
        for j, right in enumerate(b, 1):
            next_row.append(min(next_row[-1] + 1, row[j] + 1, row[j - 1] + (left != right)))
        row = next_row
    return row[-1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--model', default='base.en')
    args = parser.parse_args()
    metrics = json.loads((args.directory / 'speech-audition-metrics.json').read_text())
    model = WhisperModel(args.model, device='cpu', compute_type='int8')
    results = []
    for item in metrics:
        path = args.directory / f"{item['variant']}-{item['node']}.wav"
        # Do not provide a reference-text prompt: that could hide missing words.
        segments, _ = model.transcribe(str(path), language='en', beam_size=5,
                                       condition_on_previous_text=False, vad_filter=False)
        recognized = ' '.join(segment.text.strip() for segment in segments)
        expected, actual = words(item['text']), words(recognized)
        errors = distance(expected, actual)
        row = dict(node=item['node'], variant=item['variant'], expected=item['text'],
                   recognized=recognized, wordEdits=errors, referenceWords=len(expected),
                   wer=errors / max(1, len(expected)))
        results.append(row)
        print(f"{row['variant']}/{row['node']}: {errors} edits | {recognized}", flush=True)
    report = dict(model=args.model, runtime=importlib.metadata.version('faster-whisper'),
                  interpretation='ASR discrepancies are listening candidates, not proven synthesis errors or emotion scores.',
                  results=results)
    (args.directory / 'asr-review.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()
