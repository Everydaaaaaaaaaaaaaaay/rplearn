#!/usr/bin/env python3
"""Render owned scripts locally; never substitute source recordings for originals.

Only final AAC streams and a SHA-bound synthesis manifest are retained. Temporary
PCM/utterances are disposable; no external service, model evaluation or deployment.
"""
import argparse
import audioop
import hashlib
import json
import re
import subprocess
import struct
import tempfile
import wave
from pathlib import Path
from grade_mode_evidence import BASE, REPO

RATE = 22050


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def run(args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=45)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stderr[:500]}')


def read_pcm(path):
    """Read PCM RIFF including CoreAudio's WAVE_FORMAT_EXTENSIBLE output."""
    raw=path.read_bytes()
    assert raw[:4]==b'RIFF' and raw[8:12]==b'WAVE'
    cursor=12; fmt=data=None
    while cursor+8<=len(raw):
        tag=raw[cursor:cursor+4]; size=struct.unpack('<I',raw[cursor+4:cursor+8])[0]
        body=raw[cursor+8:cursor+8+size]
        assert len(body)==size
        if tag==b'fmt ': fmt=body
        if tag==b'data': data=body
        cursor+=8+size+(size%2)
    assert fmt is not None and data is not None
    kind,channels,rate,_,align,bits=struct.unpack('<HHIIHH',fmt[:16])
    if kind==0xfffe:
        assert len(fmt)>=40 and struct.unpack('<I',fmt[24:28])[0]==1, 'Only integer PCM subtype is accepted'
    else:
        assert kind==1
    assert (rate,channels,bits,align)==(RATE,1,16,2)
    assert data and len(data)%2==0
    return data


def render(manuscript, output, version='0.1'):
    manuscript=manuscript.resolve(); output=output.resolve()
    draft = json.loads(manuscript.read_text())
    assert draft['family'] == 'listening_extract_choice'
    assert len(draft['clips']) == draft['extracts'] == 3
    assert [len(c['questions']) for c in draft['clips']] == [2, 2, 2]
    assert draft['source_hear_each_piece_twice']
    assert output.resolve().is_relative_to((REPO/'build').resolve())
    output.mkdir(parents=True, exist_ok=True)
    assert re.fullmatch(r'\d+\.\d+',version)
    manifest_path = output/(draft['id']+f'-audio-v{version}.json')
    assert not manifest_path.exists(), 'Versioned audio manifests are immutable'
    tracks = []
    with tempfile.TemporaryDirectory(prefix='speech-work-', dir=output) as scratch:
        scratch = Path(scratch)
        utterance_cache = {}

        def speech(text, voice, speed):
            key = (voice, speed, text)
            if key not in utterance_cache:
                tag = str(len(utterance_cache))
                prompt, aiff, pcm = (scratch/(tag+s) for s in ['.txt','.aiff','.wav'])
                prompt.write_text(text)
                run(['say','-v',voice,'-r',str(speed),'-o',str(aiff),'-f',str(prompt)])
                run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}','-c','1',str(aiff),str(pcm)])
                data=read_pcm(pcm)
                assert data and audioop.max(data,2) > 0
                utterance_cache[key] = data
                prompt.unlink(); aiff.unlink(); pcm.unlink()
            return utterance_cache[key]

        for number, clip in enumerate(draft['clips'], 1):
            target = output/(draft['id']+f'-extract{number}-v{version}.m4a')
            assert not target.exists(), 'Versioned audio assets are immutable'
            parts, segments, frame = [], [], 0

            def append(data, role, text=None, speaker=None, repeat=None):
                nonlocal frame
                assert len(data)%2 == 0
                end = frame+len(data)//2
                segments.append(dict(role=role, start_frame=frame, end_frame=end,
                                     text=text, speaker=speaker, repeat=repeat,
                                     pcm_sha256=hashlib.sha256(data).hexdigest()))
                parts.append(data); frame=end

            def pause(seconds):
                append(b'\0\0'*int(seconds*RATE), 'silence')

            intro=f'Extract {number}. {clip["context"]} Questions {2*number-1} and {2*number}.'
            append(speech(intro,'Daniel',165),'introduction',intro)
            pause(8)
            for repeat in [1,2]:
                if repeat == 2:
                    prompt='Now you will hear the extract again.'
                    append(speech(prompt,'Daniel',165),'repeat_instruction',prompt)
                    pause(1)
                for turn in clip['turns']:
                    voice=draft['speakers'][turn['speaker']]
                    data=speech(turn['text'],voice['voice'],voice['words_per_minute'])
                    append(data,'dialogue',turn['text'],turn['speaker'],repeat)
                    pause(.35)
                pause(2)
            combined=scratch/f'extract{number}.wav'
            with wave.open(str(combined),'wb') as stream:
                stream.setparams((1,2,RATE,0,'NONE','not compressed'))
                for data in parts: stream.writeframes(data)
            run(['afconvert','-f','m4af','-d','aac ','-b','64000',str(combined),str(target)])
            decoded=scratch/f'decoded{number}.wav'
            run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}','-c','1',str(target),str(decoded)])
            decoded_data=read_pcm(decoded)
            decoded_frames=len(decoded_data)//2
            peak=audioop.max(decoded_data,2)
            assert abs(decoded_frames-frame) <= 4096 and peak>0
            spoken_once=' '.join(t['text'] for t in clip['turns'])
            track=dict(label=f'音频{number}（第{2*number-1}—{2*number}题）',
                       path=str(target.relative_to(REPO)), sha256=digest(target), bytes=target.stat().st_size,
                       mime_type='audio/mp4', seconds=decoded_frames/RATE,
                       response_numbers=[2*number-1,2*number], repeat_count=2,
                       dialogue_words_once=words(spoken_once),
                       spoken_words_with_instructions=2*words(spoken_once)+words(intro)+words('Now you will hear the extract again.'),
                       sample_rate=RATE, pcm_frames_before_encoding=frame,
                       decoded_frames=decoded_frames, peak_abs_sample=peak, segments=segments)
            tracks.append(track)
            combined.unlink(); decoded.unlink()
            print(json.dumps({'id':draft['id'],'extract':number,'seconds':track['seconds'],'bytes':track['bytes']}),flush=True)
    manifest=dict(version=version,id=draft['id'],manuscript={'path':str(manuscript.relative_to(BASE)), 'sha256':digest(manuscript)},
                  tool='macOS say + afconvert;local synthesis only',voices=draft['speakers'],tracks=tracks,
                  no_source_recording_reused=True,temporary_PCM_not_retained=True,whole_final_audio_decode_passed=True,
                  independent_listening_pronunciation_prosody_student_commercial_production_validated=False)
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return manifest_path


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manuscript',type=Path,action='append',required=True)
    parser.add_argument('--output',type=Path,default=REPO/'build/english-benchmark-authority-20261017/original-audio')
    parser.add_argument('--version',default='0.1',help='Fresh version for every new rendering; no existing final asset is overwritten')
    args=parser.parse_args()
    for path in args.manuscript: print(render(path,args.output,args.version))
