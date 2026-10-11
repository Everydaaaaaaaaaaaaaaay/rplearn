#!/usr/bin/env python3
"""只读复核高三、四六级逐题亲写台词的真实母版，不合成或发布。"""
import hashlib
import json
from pathlib import Path
import re
import wave
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / 'build/learning-strengthening-20261011'
CONTRACTIONS = {"i'm":"i am", "it's":"it is", "we're":"we are", "didn't":"did not",
                "we've":"we have", "isn't":"is not", "don't":"do not", "i'll":"i will",
                "i'd":"i would", "where's":"where is", "they're":"they are"}
NUMBERS = dict(zip(map(str, range(1, 13)), 'one two three four five six seven eight nine ten eleven twelve'.split()))
NUMBERS['40'] = 'forty'
ORTHOGRAPHY = {"practise":"practice", "recognise":"recognize", "week's":"weeks", "engineer's":"engineers"}


def normalized(text):
    # 只归一明确书写差异，保留实义词、时态、否定、复数s和原始识别文本。
    text = re.sub(r'\$(\d+)', r'\1 dollars', text)
    text = re.sub(r'\b1st\b', 'first', text, flags=re.I)
    words = re.findall(r"[a-zé]+(?:'[a-zé]+)?|[0-9]+", text.lower().replace('’', "'"))
    return [part for word in words for part in CONTRACTIONS.get(word, NUMBERS.get(word, ORTHOGRAPHY.get(word, word))).split()]


def read_pcm(path):
    with wave.open(str(path)) as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (24000, 1, 2)
        return np.frombuffer(audio.readframes(audio.getnframes()), dtype='<i2')


def check_recognition(evidence, expected):
    assert set(evidence) == {'base.en', 'small.en'}
    for result in evidence.values():
        assert result['exact'] and normalized(result['text']) == normalized(expected)


def local_file(path, folder):
    resolved = path.resolve(strict=True)
    assert resolved.parent == folder.resolve(), '媒体路径超出对应等级制作目录'
    return resolved


document = json.loads((ROOT / 'Backend/config/learning/authoring/strengthening-audio-review-2026-10-11.json').read_text())
audit = {c['questionId']: c for c in document['clips']}
assert len(audit) == len(document['clips']) == 11
reports = []
for name, count in [('cet4', 3), ('cet6', 3), ('senior3', 5)]:
    folder = OUTPUT / name
    read = lambda file: json.loads((folder / file).read_text())
    source = ROOT / f'Backend/config/learning/authoring/{name}-strengthening-20261011.canonical.json'
    draft = json.loads(source.read_text())
    scripts = {q['id']: q['audio']['text'] for q in draft['questions'] if q.get('audio')}
    plan = read('production-plan.json')
    assert hashlib.sha256(source.read_bytes()).hexdigest() == plan['authoringSha256']
    plans = {c['questionId']: c for c in plan['clips']}
    manifest_rows = read('manifest.json')
    manifest = {c['questionId']: c for c in manifest_rows}
    selected = read('selection.json')
    assert len(plans) == len(plan['clips']) == len(manifest) == len(manifest_rows) == count
    assert read('missing.json') == [] and len(selected) == count
    assert set(plans) == set(scripts) == set(manifest) == {c['questionId'] for c in selected}
    for row in selected:
        key = row['questionId']
        clip, expected, proof = plans[key], scripts[key], manifest[key]
        reviewed = audit[key]
        assert reviewed['level'] == name
        assert reviewed['scriptSha256'] == hashlib.sha256(expected.encode('utf-8')).hexdigest(), '审核脚本哈希不一致'
        assert row['transcript'] == clip['transcript'] == proof['transcript'] == expected == reviewed['transcript']
        assert row['segment'] == clip['id']
        for field in ['minimumWpm', 'maximumWpm', 'targetWpm']:
            assert reviewed[field] == clip[field], f'审核语速字段与计划不一致：{field}'
        assert 0 < clip['minimumWpm'] <= clip['targetWpm'] <= clip['maximumWpm']
        spoken = re.sub(r'(?:^| )([AB]): ', lambda m: '' if m.start() == 0 else ' ', expected)
        assert row['text'] == spoken == ' '.join(s['text'] for s in clip['segments'])
        assert len(clip['segments']) == len(proof['segments']) == len(row['segments']) == len(reviewed['segments']) > 0, '审核话轮数量不一致'
        assert len({s['id'] for s in clip['segments']}) == len(clip['segments']), '计划话轮编号重复'
        parts, offset = [], 0
        speakers = {}
        for index, (planned, segment, chosen, checked) in enumerate(zip(clip['segments'], proof['segments'], row['segments'], reviewed['segments'])):
            for field in ['text', 'speaker', 'voice']:
                assert checked[field] == segment[field] == chosen[field] == planned[field], f'审核话轮身份不一致：{field}'
            assert chosen['segment'] == planned['id'], '选用话轮顺序与计划不一致'
            for field in ['take', 'speed', 'steps']:
                assert checked[field] == segment[field] == chosen[field], f'审核制作参数不一致：{field}'
            # 渲染器以Float32保存速率，允许序列化的微小精度差，不允许变更制作参数。
            assert abs(chosen['speed'] - planned['rate']) < 1e-6, '选用速率与计划不一致'
            assert segment['expression'] == chosen['expression']
            assert speakers.setdefault(planned['speaker'], planned['voice']) == planned['voice'], '同一说话人不能中途换声线'
            path = local_file(Path(segment['sourcePath']), folder)
            assert path == local_file(folder / chosen['pcmFile'], folder)
            assert checked['file'] == path.relative_to(ROOT).as_posix(), '审核话轮文件与选用文件不一致'
            assert hashlib.sha256(path.read_bytes()).hexdigest() == checked['sha256'] == segment['sha256'] == chosen['sha256'], '审核话轮字节哈希不一致'
            assert chosen['byteSize'] == path.stat().st_size
            # 将选用记录继续绑定到当次渲染的原始记录，避免整套审核参数一起漂移。
            rendered = local_file(folder / chosen['file'], folder)
            assert hashlib.sha256(rendered.read_bytes()).hexdigest() == chosen['sourceSha256']
            rendering = json.loads(rendered.with_suffix('.json').read_text())
            for field in ['segment', 'text', 'speaker', 'voice', 'take', 'speed', 'steps', 'expression', 'file']:
                assert chosen[field] == rendering[field], f'选用记录与原始渲染记录不一致：{field}'
            samples = read_pcm(path).astype(np.float64)
            assert checked['startSample'] == segment['startSample'] == offset, '审核话轮开始位置不一致'
            offset += len(samples)
            assert checked['endSampleExclusive'] == segment['endSampleExclusive'] == offset, '审核话轮结束位置不一致'
            parts.append(samples)
            check_recognition(segment['candidateRecognition'], segment['text'])
            assert checked['recognition'] == segment['candidateRecognition'] == chosen['recognition']
            if index < len(clip['segments']) - 1:
                gap = proof['gaps'][index]
                assert gap == {'startSample': offset, 'endSampleExclusive': offset + 7200}
                parts.append(np.zeros(7200)); offset += 7200
        assert len(proof['gaps']) == len(clip['segments']) - 1
        assert row['speakers'] == [{'id': speaker, 'voice': voice} for speaker, voice in speakers.items()]
        assert len(set(speakers.values())) == len(speakers), '不同说话人必须使用不同声线'
        assert reviewed['voice'] == row['voice'] == '+'.join(speakers.values()), '审核整体声线不一致'
        assert row['interSegmentSilenceMs'] == (300 if proof['gaps'] else 0)
        assert proof['insertedGapSamples'] == (7200 if proof['gaps'] else 0)
        assert proof['sampleRate'] == 24000
        original = np.concatenate(parts)
        gain = min(3000 / float(np.sqrt(np.mean(original * original))), 27000 / float(np.abs(original).max()))
        assert abs(gain - row['gain']) < 1e-12 and row['gain'] == proof['gain']
        master = local_file(Path(row['masterPath']), folder)
        assert master == local_file(Path(proof['masterPath']), folder) == local_file(folder / row['masterFile'], folder)
        assert row['masterFile'] == clip['id'] + '.wav'
        assert reviewed['file'] == master.relative_to(ROOT).as_posix(), '审核母版文件与实际母版不一致'
        pcm = read_pcm(master)
        assert np.array_equal(pcm, np.rint(original * gain).astype('<i2')), '母版只能包含完整话轮、增益和轮间静音'
        digest = hashlib.sha256(master.read_bytes()).hexdigest()
        assert digest == proof['masterSha256'] == row['masterStats']['sha256'] == audit[key]['sha256']
        active = np.flatnonzero(np.abs(pcm.astype(np.int32)) > 128)
        assert len(active) and active[0] / 24000 < .7 and (len(pcm) - 1 - active[-1]) / 24000 < .9
        assert np.abs(pcm.astype(np.int32)).max() <= 27000
        seconds = len(pcm) / 24000
        assert 0 < seconds < 60
        wpm = len(spoken.split()) / seconds * 60
        assert abs(wpm - row['wpm']) < 1e-9 and clip['minimumWpm'] <= wpm <= clip['maximumWpm']
        check_recognition(row['masterRecognition'], spoken)
        assert audit[key]['masterRecognition'] == row['masterRecognition']
        assert audit[key]['byteSize'] == master.stat().st_size
        assert audit[key]['durationMs'] == round(seconds * 1000)
        assert audit[key]['wpm'] == round(wpm, 2)
        reports.append({'questionId': key, 'wpm': round(wpm, 2), 'sha256': digest})
assert set(audit) == {c['questionId'] for c in reports}
print(json.dumps({'count': len(reports), 'clips': reports,
                  'scope': '台词、双ASR、完整话轮逐采样、波形、语速与审核绑定通过；未声称独立人耳或正式发布通过。'}, ensure_ascii=False, indent=2))
