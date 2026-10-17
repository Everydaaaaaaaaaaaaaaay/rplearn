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


def render(manuscript, output, version='0.1', reuse_manifest=None, render_only=None):
    manuscript=manuscript.resolve(); output=output.resolve()
    draft = json.loads(manuscript.read_text())
    family=draft['family']
    assert family in {'listening_extract_choice','listening_interview_choice','listening_double_matching','listening_sentence_completion','listening_true_false','listening_short_conversation_choice','listening_multi_question_choice','listening_dialogue_choice','listening_picture_true_false','listening_word_phrase_choice','listening_passage_completion','listening_picture_matching','listening_long_conversation_choice','listening_passage_choice','listening_table_completion','listening_passage_true_false','listening_picture_choice'}
    if draft.get('illustrated_listening'):
        from illustrated_listening_contract import validate_draft
        validate_draft(draft)
    elif draft.get('senior_short_source_bound'):
        from senior_short_listening_contract import validate_draft
        validate_draft(draft)
    elif draft.get('junior_source_bound'):
        from junior_listening_contract import validate_draft
        validate_draft(draft)
    elif family=='listening_passage_true_false':
        assert draft['grade']=='primary6' and len(draft['clips'])==1
        assert draft['source_replay_rule']=='not_printed' and draft['render_repeat_count']==1
        c=draft['clips'][0];assert len(c['questions'])==5 and len(c['turns'])==1 and c['turns'][0]['speaker']=='N'
        assert c['preview_seconds']==c['answer_seconds']==25
        assert all([k for k,_ in q['options']]==['T','F']for q in c['questions'])
    elif family=='listening_picture_matching':
        assert (draft['grade'],len(draft['figures']))in {('primary3',5),('primary6',6)} and len(draft['clips'])==1
        assert draft['source_replay_rule']=='not_printed' and draft['render_repeat_count']==1
        c=draft['clips'][0];units=draft['audio_dialogue_units']
        assert [u['label']for u in units]==list('ABCDEF'[:len(draft['figures'])]) and len(c['questions'])==len(draft['figures'])
        assert c['turns']==[t for u in units for t in [dict(speaker='N',text='Dialogue '+u['label']+'.')]+u['turns']]
        assert all([t['speaker']for t in u['turns']]==['M','W']for u in units)
        assert c['preview_seconds']==c['answer_seconds']==15
    elif family=='listening_passage_completion':
        assert len(draft['clips'])==1 and draft['source_repeat_count']==3
        c=draft['clips'][0]
        assert len(c['questions'])==5 and len(c['turns'])==1 and c['turns'][0]['speaker']=='N'
        assert all(not q['options'] and q['acceptedAnswers']for q in c['questions'])
        assert c['preview_seconds']==c['answer_seconds']==25
    elif family=='listening_word_phrase_choice':
        assert len(draft['clips'])==draft['source_sentences']==10 and draft['source_hear_each_piece_twice']
        assert all(len(c['questions'])==len(c['turns'])==1 and c['turns'][0]['speaker']=='N' and [k for k,_ in c['questions'][0]['options']]==['A','B','C'] and c['preview_seconds']==2 and c['answer_seconds']==3 for c in draft['clips'])
    elif family=='listening_picture_true_false':
        assert (draft['grade'],draft['source_sentences'])in {('primary3',10),('primary6',9)}
        assert len(draft['clips'])==draft['source_sentences']
        assert draft['source_replay_rule']=='not_printed' and draft['render_repeat_count']==1
        assert all(len(c['questions'])==len(c['turns'])==1 and c['turns'][0]['speaker']=='N' and [k for k,_ in c['questions'][0]['options']]==['T','F'] and c['preview_seconds']==2 and c['answer_seconds']==3 for c in draft['clips'])
    elif family=='listening_dialogue_choice':
        if draft['grade']=='primary6':
            assert [len(c['questions'])for c in draft['clips']]==draft['source_questions_per_clip']==[1,2,2]
            assert draft['source_replay_rule']=='not_printed' and draft['render_repeat_count']==1
        else:
            assert draft['grade']=='primary5' and draft['source_repeat_count']==3
            assert len(draft['clips'])==1 and len(draft['clips'][0]['questions'])==5
        for c in draft['clips']:
            assert set(t['speaker']for t in c['turns'])=={'M','W'}
            assert c['preview_seconds']==c['answer_seconds']==5*len(c['questions'])
            assert all(len(q['options'])==3 for q in c['questions'])
    elif family=='listening_multi_question_choice':
        assert [len(c['questions'])for c in draft['clips']]==draft['source_questions_per_clip']
        assert len(draft['clips'])>=2 and draft['source_hear_each_piece_twice']
        for i,c in enumerate(draft['clips']):
            assert set(t['speaker']for t in c['turns'])==({'N'}if i==len(draft['clips'])-1 else {'M','W'})
            assert c['preview_seconds']==c['answer_seconds']==5*len(c['questions'])
            assert all(len(q['options'])==3 for q in c['questions'])
    elif family=='listening_short_conversation_choice':
        assert len(draft['clips'])==5
        assert all(len(c['questions'])==1 and len(c['questions'][0]['options'])==3 for c in draft['clips'])
        assert all(set(t['speaker']for t in c['turns'])=={'M','W'}for c in draft['clips'])
        assert all(c['preview_seconds']==0 and c['answer_seconds']==10 for c in draft['clips'])
    elif family=='listening_extract_choice':
        assert len(draft['clips']) == draft['extracts'] == 3
        assert [len(c['questions']) for c in draft['clips']] == [2,2,2]
    else:
        assert len(draft['clips'])==1
        clip=draft['clips'][0]
        if family=='listening_interview_choice':
            assert len(clip['questions'])==6
            assert set(t['speaker'] for t in clip['turns'])=={'I','G1','G2'}
            assert all(len(q['options'])==4 for q in clip['questions'])
        elif family=='listening_sentence_completion':
            assert len(clip['questions'])==8
            assert len(clip['turns'])==1 and clip['turns'][0]['speaker']=='N'
            assert all(not q['options'] and q['acceptedAnswers'] for q in clip['questions'])
        elif family=='listening_true_false':
            assert len(clip['questions'])==4 and len({t['speaker']for t in clip['turns']})==3
            assert all([k for k,_ in q['options']]==['T','F']for q in clip['questions'])
        else:
            assert len(clip['questions'])==10
            assert [t['speaker'] for t in clip['turns']]==['S1','S2','S3','S4','S5']
            assert len(draft['banks'])==2 and all(len(b['options'])==8 for b in draft['banks'])
            assert all(q['options']==draft['banks'][i//5]['options'] for i,q in enumerate(clip['questions']))
    if draft.get('illustrated_listening'):
        repeat_count=draft['render_repeat_count']
    elif draft.get('junior_source_bound') or draft.get('senior_short_source_bound'):
        repeat_count=draft['source_repeat_count']
    elif family=='listening_passage_completion' or family=='listening_dialogue_choice' and draft['grade']=='primary5':
        assert draft['source_repeat_count']==3
        repeat_count=3
    elif family in {'listening_dialogue_choice','listening_picture_true_false','listening_picture_matching','listening_passage_true_false'}:
        repeat_count=1
    elif family=='listening_short_conversation_choice':
        assert draft['source_hear_each_piece_once'] and draft['source_answer_seconds']==10
        repeat_count=1
    elif family=='listening_true_false':
        assert draft['source_replay_rule']=='not_explicit' and draft['render_repeat_count']==1
        repeat_count=1
    else:
        assert draft['source_hear_each_piece_twice']
        repeat_count=2
    assert output.resolve().is_relative_to((REPO/'build').resolve())
    output.mkdir(parents=True, exist_ok=True)
    assert re.fullmatch(r'\d+\.\d+',version)
    manifest_path = output/(draft['id']+f'-audio-v{version}.json')
    assert not manifest_path.exists(), 'Versioned audio manifests are immutable'
    prior=None
    if reuse_manifest is not None:
        reuse_manifest=Path(reuse_manifest).resolve();prior=json.loads(reuse_manifest.read_text())
        assert prior['id']==draft['id'] and prior['manuscript']==dict(path=str(manuscript.relative_to(BASE)),sha256=digest(manuscript))
        assert prior['whole_final_audio_decode_passed'] and len(prior['tracks'])==len(draft['clips'])
        assert render_only and set(render_only)<=set(range(1,len(draft['clips'])+1))
    else:assert render_only is None
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
            if prior is not None and number not in render_only:
                reused=prior['tracks'][number-1];oldpath=REPO/reused['path']
                assert oldpath.stat().st_size==reused['bytes'] and digest(oldpath)==reused['sha256']
                tracks.append(reused);continue
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

            start_response=sum(len(c['questions'])for c in draft['clips'][:number-1])+1
            response_numbers=(list(range(start_response,start_response+len(clip['questions'])))if draft.get('illustrated_listening') or draft.get('junior_source_bound') or family in {'listening_multi_question_choice','listening_dialogue_choice'}else [number] if family in {'listening_short_conversation_choice','listening_picture_true_false','listening_word_phrase_choice'} else [2*number-1,2*number] if family=='listening_extract_choice'
                              else list(range(1,len(clip['questions'])+1)))
            intro=(f'Part {number}. Read questions {response_numbers[0]} to {response_numbers[-1]}.'if draft.get('illustrated_listening') or draft.get('junior_source_bound') or family in {'listening_multi_question_choice','listening_dialogue_choice'}else f'Text {number}.' if family in {'listening_short_conversation_choice','listening_picture_true_false','listening_word_phrase_choice'} else f'Extract {number}. {clip["context"]} Questions {2*number-1} and {2*number}.'
                   if family=='listening_extract_choice' else draft['audio_introduction'])
            if draft.get('illustrated_listening'):intro='Text '+str(number)+'.'if draft['grade']=='primary5'else draft['audio_introduction']
            example_words=0
            if number==1 and draft.get('worked_example'):
                example=draft['worked_example'];q=example['question']
                example_intro='Here is an example.'
                append(speech(example_intro,'Daniel',165),'worked_example_instruction',example_intro)
                example_words+=words(example_intro)
                for turn in example['turns']:
                    voice=draft['speakers'][turn['speaker']]
                    speed=voice['rate_parameter'] if 'rate_parameter'in voice else voice['words_per_minute']
                    append(speech(turn['text'],voice['voice'],speed),'worked_example',turn['text'],turn['speaker'],1)
                    example_words+=words(turn['text']);pause(.35)
                solution=q['stem']+' '+ ' '.join(k+'. '+v for k,v in q['options'])+' The answer is '+q['answer']+'.'
                append(speech(solution,'Daniel',150),'worked_example_solution',solution)
                example_words+=words(solution);pause(2)
            append(speech(intro,'Daniel',165),'introduction',intro)
            pause(clip.get('preview_seconds',8))
            repeat_prompt=('Now you will hear the extract again.' if family=='listening_extract_choice'
                           else 'Now you will hear the whole recording again.')
            for repeat in range(1,repeat_count+1):
                if repeat > 1:
                    append(speech(repeat_prompt,'Daniel',165),'repeat_instruction',repeat_prompt)
                    pause(1)
                for turn_index,turn in enumerate(clip['turns']):
                    if family=='listening_double_matching':
                        prompt='Speaker '+turn['speaker'][1:]+'.'
                        append(speech(prompt,'Daniel',165),'speaker_announcement',prompt,repeat=repeat)
                        pause(.6)
                    voice=draft['speakers'][turn['speaker']]
                    speed=voice['rate_parameter']if 'rate_parameter'in voice else voice['words_per_minute']
                    data=speech(turn['text'],voice['voice'],speed)
                    append(data,'dialogue',turn['text'],turn['speaker'],repeat)
                    if family!='listening_short_conversation_choice' or turn_index<len(clip['turns'])-1:
                        pause(2 if family=='listening_double_matching' else .35)
                pause(1 if (draft.get('junior_source_bound') or family in {'listening_multi_question_choice','listening_word_phrase_choice','listening_passage_completion','listening_dialogue_choice'})and repeat<repeat_count else clip.get('answer_seconds',2))
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
            speech_frames=sum(s['end_frame']-s['start_frame']for s in segments if s['role']=='dialogue')
            estimated_word_rate=repeat_count*words(spoken_once)/(speech_frames/RATE)*60
            announcement_words=(sum(words('Speaker '+t['speaker'][1:]+'.') for t in clip['turns'])*2
                                if family=='listening_double_matching' else 0)
            track=dict(label=f'音频{number}（第{response_numbers[0]}—{response_numbers[-1]}题）',
                       path=str(target.relative_to(REPO)), sha256=digest(target), bytes=target.stat().st_size,
                       mime_type='audio/mp4', seconds=decoded_frames/RATE,
                       response_numbers=response_numbers, repeat_count=repeat_count,
                       dialogue_words_once=words(spoken_once),
                       dialogue_seconds_excluding_added_pauses=speech_frames/RATE,
                       observed_English_word_tokens_per_minute=estimated_word_rate,
                       rate_parameter_not_actual_word_rate_or_difficulty=True,
                       spoken_words_with_instructions=repeat_count*words(spoken_once)+words(intro)+(repeat_count-1)*words(repeat_prompt)+announcement_words+example_words,
                       sample_rate=RATE, pcm_frames_before_encoding=frame,
                       decoded_frames=decoded_frames, peak_abs_sample=peak, segments=segments)
            if example_words:track.update(worked_example_spoken_words=example_words,worked_example_assessed_responses=0)
            tracks.append(track)
            combined.unlink(); decoded.unlink()
            print(json.dumps({'id':draft['id'],'extract':number,'seconds':track['seconds'],'bytes':track['bytes']}),flush=True)
    manifest=dict(version=version,id=draft['id'],manuscript={'path':str(manuscript.relative_to(BASE)), 'sha256':digest(manuscript)},
                  tool='macOS say + afconvert;local synthesis only',voices=draft['speakers'],tracks=tracks,
                  no_source_recording_reused=True,temporary_PCM_not_retained=True,whole_final_audio_decode_passed=True,
                  independent_listening_pronunciation_prosody_student_commercial_production_validated=False)
    if prior is not None:manifest.update(reused_verified_audio_manifest=dict(path=str(reuse_manifest.relative_to(REPO)),sha256=digest(reuse_manifest)),rerendered_track_numbers=list(render_only),unchanged_tracks_reused_without_copy=True)
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return manifest_path


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manuscript',type=Path,action='append',required=True)
    parser.add_argument('--output',type=Path,default=REPO/'build/english-benchmark-authority-20261017/original-audio')
    parser.add_argument('--version',default='0.1',help='Fresh version for every new rendering; no existing final asset is overwritten')
    args=parser.parse_args()
    for path in args.manuscript: print(render(path,args.output,args.version))
