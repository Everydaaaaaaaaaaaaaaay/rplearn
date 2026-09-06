#!/usr/bin/env python3
"""Select locally generated takes, calibrate real gaps and export a prepared audition.

uv run --with faster-whisper python Scripts/master-story-speech.py OUTPUT --result RUN.xcresult
All audio and recognition stay local. Selection is an engineering screen, not a human emotion rating.
"""
import argparse
import base64
import hashlib
import html
import json
import math
import re
import shutil
import subprocess
import tempfile
import wave
from pathlib import Path
import numpy as np

RATE = 44100
FRAME = 441


def tokens(text):
    return re.findall(r"[a-z]+(?:'[a-z]+)?", text.lower().replace('’', "'"))


def edit_distance(a, b):
    row = list(range(len(b) + 1))
    for i, word in enumerate(a, 1):
        new = [i]
        for j, other in enumerate(b, 1):
            new.append(min(new[-1] + 1, row[j] + 1, row[j-1] + (word != other)))
        row = new
    return row[-1]


def read_audio(path):
    raw = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', str(path), '-f', 'f32le',
                                   '-ac', '1', '-ar', str(RATE), '-'])
    audio = np.frombuffer(raw, dtype='<f4').copy()
    if len(audio) == 0 or not np.isfinite(audio).all() or np.max(np.abs(audio)) <= .001:
        raise ValueError(f'Invalid/silent waveform: {path}')
    return audio


def write_audio(path, audio):
    if not np.isfinite(audio).all() or np.max(np.abs(audio)) >= 1:
        raise ValueError('Refusing to export clipped/nonfinite audio')
    with wave.open(str(path), 'wb') as stream:
        stream.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        stream.writeframes(np.rint(audio * 32767).astype('<i2').tobytes())


def activity(audio):
    # Very low threshold; this is an edge-silence detector, not speech VAD.
    # Preserve quiet aspiration/tails instead of trimming to ASR word timestamps.
    padded = np.pad(audio, (0, (-len(audio)) % FRAME))
    rms = np.sqrt(np.mean(padded.reshape(-1, FRAME).astype(np.float64) ** 2, axis=1))
    active = np.flatnonzero(rms > .00012)  # about -78 dBFS
    if not len(active):
        raise ValueError('No safely detectable activity')
    return int(active[0] * FRAME), min(len(audio), int((active[-1] + 1) * FRAME)), rms


def trim_edges(audio, preserve_expression=False):
    first, last, _ = activity(audio)
    start = 0 if preserve_expression else max(0, first - int(.1 * RATE))
    end = min(len(audio), last + int(.12 * RATE))
    trimmed = audio[start:end].copy()
    # Only taper the retained, near-silent outer margin. Never crossfade speech.
    fade = min(int(.005 * RATE), len(trimmed) // 2)
    if fade and np.max(np.abs(trimmed[:fade])) < .00012:
        trimmed[:fade] *= np.linspace(0, 1, fade)
    if fade and np.max(np.abs(trimmed[-fade:])) < .00012:
        trimmed[-fade:] *= np.linspace(1, 0, fade)
    return trimmed, start, len(audio) - end


def active_rms(audio):
    _, _, rms = activity(audio)
    values = rms[rms > max(.001, np.max(rms) * .06)]
    return float(np.sqrt(np.mean(values ** 2)))


def assemble(parts, desired_gaps):
    if len(parts) != len(desired_gaps) or not parts:
        raise ValueError('A gap is required for every prepared segment')
    output, offsets, gaps = [], [], []
    size = 0
    for i, part in enumerate(parts):
        if i:
            _, previous_end, _ = activity(parts[i-1])
            next_start, _, _ = activity(part)
            retained = (len(parts[i-1]) - previous_end + next_start) / RATE
            added = max(0, desired_gaps[i-1] - retained)
            count = round(added * RATE)
            output.append(np.zeros(count, dtype=np.float32)); size += count
            gaps.append(dict(target=desired_gaps[i-1], retained=retained,
                             inserted=count / RATE, measured=retained + count / RATE))
        offsets.append(size / RATE)
        output.append(part); size += len(part)
    output.append(np.zeros(round(desired_gaps[-1] * RATE), dtype=np.float32))
    return np.concatenate(output), offsets, gaps


def export_candidates(result, output):
    with tempfile.TemporaryDirectory(dir=output) as temporary:
        subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result),
                        '--output-path', temporary], check=True, stdout=subprocess.DEVNULL)
        data = json.loads((Path(temporary) / 'manifest.json').read_text())
        seen = set()
        for test in data:
            for item in test['attachments']:
                name = re.sub(r'_\d+_[A-Fa-f0-9-]{36}(?=\.)', '', item['suggestedHumanReadableName'])
                if not re.fullmatch(r'(?:candidate-|performance-)[\w-]+\.(?:wav|json)', name):
                    continue
                if name in seen:
                    raise ValueError('Duplicate candidate attachment; use a single device/run')
                seen.add(name)
                shutil.copyfile(Path(temporary) / item['exportedFileName'], output / name)


def loudness_match(source, destination, target=-22):
    # Two-pass linear gain, no compressor/reverb/denoising/pitch processing.
    first = subprocess.run(['ffmpeg', '-hide_banner', '-i', str(source), '-af',
        f'loudnorm=I={target}:TP=-2:LRA=11:print_format=json', '-f', 'null', '-'],
        capture_output=True, text=True, check=True)
    measurement, _ = json.JSONDecoder().raw_decode(first.stderr[first.stderr.rfind('{'):])
    gain = target - float(measurement['input_i'])
    peak = float(measurement['input_tp']) + gain
    if peak > -2:
        gain -= peak + 2  # preserve headroom instead of using a limiter
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(source), '-af', f'volume={gain}dB',
                    '-ar', str(RATE), '-c:a', 'pcm_s16le', str(destination)], check=True)
    return dict(measuredLUFS=float(measurement['input_i']), gainDB=gain,
                resultingLUFS=float(measurement['input_i']) + gain,
                predictedTruePeak=float(measurement['input_tp']) + gain)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--result', type=Path)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--story', type=Path, default=Path('App/Resources/Stories/departures_london_v1.json'))
    parser.add_argument('--model', default='base.en')
    args = parser.parse_args()
    output = args.output; output.mkdir(parents=True, exist_ok=True)
    if args.result: export_candidates(args.result, output)
    plan = json.loads((output / 'performance-plan.json').read_text())
    candidates = json.loads((output / 'performance-candidates.json').read_text())
    story = {node['id']: node for node in json.loads(args.story.read_text())['nodes']}
    from faster_whisper import WhisperModel
    model = WhisperModel(args.model, device='cpu', compute_type='int8')
    cache_path = output / 'candidate-recognition.json'
    cache = json.loads(cache_path.read_text()) if cache_path.exists() else {}
    evaluated = []
    for item in candidates:
        path = output / item['file']; digest = hashlib.sha256(path.read_bytes()).hexdigest()
        key = args.model + ':' + digest
        if key not in cache:
            recognized, _ = model.transcribe(str(path), language='en', beam_size=5,
                condition_on_previous_text=False, word_timestamps=True, vad_filter=False)
            words = [dict(text=word.word, start=word.start, end=word.end)
                     for segment in recognized for word in segment.words]
            cache[key] = words
            cache_path.write_text(json.dumps(cache, ensure_ascii=False, indent=2) + '\n')
        words = cache[key]
        text = ''.join(word['text'] for word in words)
        audio = read_audio(path); first, last, rms = activity(audio)
        expected, actual = tokens(item['text']), tokens(text)
        row = dict(item, recognized=text, words=words, wordEdits=edit_distance(expected, actual),
                   activeSeconds=(last-first)/RATE, activeRMS=active_rms(audio),
                   peak=float(np.max(np.abs(audio))), sha256=digest)
        evaluated.append(row)
        print(f"candidate {item['segment']}/{item['take']}: {row['wordEdits']} ASR edits", flush=True)
    selected, parts = [], []
    for segment in plan['segments']:
        eligible = [item for item in evaluated if item['segment'] == segment['id']
                    and item['wordEdits'] == 0 and item['peak'] < .95]
        if not eligible:
            (output/'candidate-review.json').write_text(json.dumps(evaluated, ensure_ascii=False, indent=2))
            raise ValueError(f"No transcript-clean candidate for {segment['id']}; review/re-render before delivery")
        center = float(np.median([item['activeSeconds'] for item in eligible]))
        level = float(np.median([item['activeRMS'] for item in eligible]))
        # Prefer a representative fluent take, not the loudest, fastest or most
        # dramatic one. These tie-breaks do not claim to measure emotional quality.
        for item in eligible:
            item['selectionScore'] = (abs(math.log(item['activeSeconds']/center))
                + .03*abs(20*math.log10(item['activeRMS']/level))
                + (.035 if segment['breath'] and item['expression']=='none' else 0))
        choice = min(eligible, key=lambda item: (item['selectionScore'], item['take']))
        part, start, tail = trim_edges(read_audio(output/choice['file']), choice['expression'] != 'none')
        choice = dict(choice, trimmedStart=start/RATE, trimmedTail=tail/RATE,
                      intention=segment['intention'], gapAfter=segment['gapAfter'])
        selected.append(choice); parts.append(part)
    # A small gain per CAST, not per line; retain within-character dynamics.
    levels = {speaker: float(np.median([active_rms(part) for row,part in zip(selected,parts)
                                       if row['speaker']==speaker]))
              for speaker in {row['speaker'] for row in selected}}
    target = float(np.median(list(levels.values())))
    gains = {speaker: max(-1.5,min(1.5,20*math.log10(target/level))) for speaker,level in levels.items()}
    parts = [part * 10**(gains[row['speaker']]/20) for row,part in zip(selected,parts)]
    audio, offsets, gaps = assemble(parts, [segment['gapAfter'] for segment in plan['segments']])
    write_audio(output/'prepared-unmastered.wav', audio)
    mastering = loudness_match(output/'prepared-unmastered.wav',output/'performance-dry.wav')
    baseline_mastering = loudness_match(args.baseline,output/'original-matched.wav')
    # Preserve original panel ownership even where synthesis crosses panels.
    owners = [id for id in plan['sourceNodes'] for _ in tokens(story[id]['text'])]
    timed = []
    for row, offset in zip(selected, offsets):
        for word in row['words']:
            for token in tokens(word['text']):
                timed.append(dict(token=token,start=offset+max(0,word['start']-row['trimmedStart']),
                                  end=offset+max(0,word['end']-row['trimmedStart'])))
    expected = tokens(' '.join(story[id]['text'] for id in plan['sourceNodes']))
    if [word['token'] for word in timed] != expected: raise ValueError('Subtitle alignment lost/reordered words')
    timeline=[]
    for id in plan['sourceNodes']:
        words = [word for owner,word in zip(owners,timed) if owner==id]
        timeline.append(dict(id=id,start=words[0]['start'],end=words[-1]['end'],
                             text=story[id]['text'],translation=story[id]['translation'],speaker=story[id]['speaker']))
    (output/'timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2)+'\n')
    def stamp(t):
        ms=round(t*1000);return f'{ms//3600000:02}:{ms//60000%60:02}:{ms//1000%60:02}.{ms%1000:03}'
    vtt=['WEBVTT','']
    for cue in timeline:
        vtt += [f'{stamp(cue["start"])} --> {stamp(cue["end"])}',cue['text'],cue['translation'],'']
    (output/'performance.vtt').write_text('\n'.join(vtt)+'\n')
    # Optional quiet room version, original deterministic rain only. Fade the
    # bed gently and keep it 25 dB below active dialogue; dry version stays primary.
    dry = read_audio(output/'performance-dry.wav');rain=read_audio(output/'performance-rain.wav')
    bed=np.resize(rain,len(dry));bed*=active_rms(dry)*10**(-25/20)/np.sqrt(np.mean(bed**2))
    fade=min(RATE,len(bed)//2);bed[:fade]*=np.linspace(0,1,fade);bed[-fade:]*=np.linspace(1,0,fade)
    write_audio(output/'performance-room.wav',dry+bed)
    report=dict(model=args.model,selection='Transcript-clean, central duration and active loudness; preserve contextual breath when otherwise comparable. No human emotion scoring.',
        seconds=len(audio)/RATE,candidates=len(evaluated),selected=selected,gaps=gaps,speakerGainDB=gains,
        mastering=mastering,baselineMastering=baseline_mastering,subtitleTiming='Local ASR word alignment; approximate, not manually corrected',
        limitations=['No human listening claim.','Only an audition pack; full App pagination/preload integration is not claimed.',
        'The 70-character Core ML cap is preserved.','Silent player question is represented by a beat, not full interactive reading time.'])
    (output/'performance-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    (output/'candidate-review.json').write_text(json.dumps(evaluated,ensure_ascii=False,indent=2)+'\n')
    make_page(output,timeline,report)
    print(f'Prepared audition: {output.resolve()}/performance-dry.wav ({len(audio)/RATE:.2f}s)',flush=True)


def make_page(output,timeline,report):
    encoded=json.dumps(timeline,ensure_ascii=False).replace('</','<\\/')
    body=f'''<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>伦敦 · 连贯演绎试听</title>
<style>body{{font:17px/1.7 system-ui;background:#f5f2eb;color:#302c29;max-width:920px;margin:42px auto;padding:0 22px}}h1{{font-size:32px}}section{{padding:18px 0;border-bottom:1px solid #d9d2c6}}audio{{width:100%}}#caption{{min-height:140px;background:#fffaf1;border-radius:16px;padding:24px}}#en{{font-size:23px}}small,#zh{{color:#736b61}}button{{font:inherit;border:1px solid #d9d2c6;background:transparent;border-radius:8px;padding:10px;text-align:left;width:100%;margin:5px 0;cursor:pointer}}</style>
<h1>给 Oliver 一点喘息的空间</h1><p>完整句意合成、实测停顿、候选筛选、适度响度平衡。所有音频已准备好，播放时不等待模型。</p>
<section><h2>整合试听版 · {report['seconds']:.1f} 秒</h2><audio id="main" controls preload="auto" src="performance-dry.wav"></audio><div id="caption"><small id="who">Oliver / Nora / 旁白</small><div id="en">按播放开始试听</div><div id="zh"></div></div></section>
<section><h2>原版 · 已匹配整体响度</h2><audio controls preload="none" src="original-matched.wav"></audio></section>
<section><h2>可选：轻微书店雨声</h2><audio controls preload="none" src="performance-room.wav"></audio></section>
<p><small>保留原文和固定音色；静音玩家问句以交流节拍表示。字幕来自本地词级时间对齐。自动筛选不是人类听感评分。</small></p><h2>台词定位</h2>'''
    for cue in timeline:
        body+=f'<button data-time="{cue["start"]}">{html.escape(cue["speaker"])} · {html.escape(cue["text"])}</button>'
    body+='''<script>const cues='''+encoded+''';const main=document.getElementById('main');main.addEventListener('timeupdate',()=>{const c=cues.find(x=>main.currentTime>=x.start&&main.currentTime<=x.end);if(c){document.getElementById('who').textContent=c.speaker;document.getElementById('en').textContent=c.text;document.getElementById('zh').textContent=c.translation;}});document.querySelectorAll('button').forEach(b=>b.onclick=()=>{main.currentTime=Number(b.dataset.time);main.play()});document.addEventListener('play',e=>{document.querySelectorAll('audio').forEach(a=>{if(a!==e.target)a.pause()})},true)</script></html>'''
    # Self-contained audio makes seeking work from file:// too; no reliance on
    # a development server's HTTP Range implementation or ongoing process.
    for name in ['performance-dry', 'original-matched', 'performance-room']:
        encoded_audio = base64.b64encode((output/f'{name}.wav').read_bytes()).decode('ascii')
        body = body.replace(f'src="{name}.wav"', f'src="data:audio/wav;base64,{encoded_audio}"')
    (output/'index.html').write_text(body,encoding='utf-8')


if __name__=='__main__':main()
