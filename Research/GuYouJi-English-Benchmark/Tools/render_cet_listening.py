#!/usr/bin/env python3
"""Owned CET listening sections: one play, spoken questions, printed options only."""
import argparse
import audioop
import json
import re
import tempfile
import wave
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from render_original_listening import RATE, digest, read_pcm, run, words
from compile_original_listening import ref
from quality_review_contract import response_markdown

FAMILIES = {'listening_news_choice','listening_long_conversation_choice',
            'listening_passage_choice','listening_lecture_choice'}


def contract(draft):
    source_index = BASE/draft['source_index']
    source = next(s for s in json.loads(source_index.read_text())['groups']
                  if s['id']==draft['source_group_id'])
    assert source['kind']==draft['family'] in FAMILIES
    assert source['level']==draft['grade'] in {'undergraduate','postgraduate'}
    assert source['full_student_input'] and not source['is_independent_gold']
    assert source['material']['source_repeat_count']==draft['repeat_count']==1
    assert source['material']['questions_spoken_after_each_piece']
    assert not source['material']['student_paper_prints_questions']
    assert draft['question_pause_seconds']==15
    assert len(draft['clips'])==source['material']['pieces']
    assert [len(c['questions'])for c in draft['clips']]==source['material']['responses_per_piece']
    for clip in draft['clips']:
        assert clip['turns'] and all(t['speaker']in draft['speakers'] and t['text']for t in clip['turns'])
        for q in clip['questions']:
            assert q['spoken_question'] and q['rationale']
            assert len(q['options'])==4 and [k for k,_ in q['options']]==list('ABCD')
            assert q['answer']in dict(q['options'])
    assert sum(len(c['questions'])for c in draft['clips'])==source['responses']
    return source_index, source


def render(manuscript, output, version):
    manuscript, output = manuscript.resolve(), output.resolve()
    draft=json.loads(manuscript.read_text());_,source=contract(draft)
    assert re.fullmatch(r'\d+\.\d+',version)
    assert output.resolve().is_relative_to((REPO/'build').resolve())
    output.mkdir(parents=True,exist_ok=True)
    target=output/(draft['id']+f'-section-v{version}.m4a')
    manifest_path=output/(draft['id']+f'-audio-v{version}.json')
    assert not target.exists() and not manifest_path.exists()
    parts,segments,frame=[],[],0
    with tempfile.TemporaryDirectory(prefix='cet-speech-work-',dir=output) as tmp:
        scratch=Path(tmp);cache={}
        def speech(text,speaker='N'):
            voice=draft['speakers'][speaker];key=(text,voice['voice'],voice['words_per_minute'])
            if key not in cache:
                tag=str(len(cache));prompt=scratch/(tag+'.txt');aiff=scratch/(tag+'.aiff');pcm=scratch/(tag+'.wav')
                prompt.write_text(text)
                run(['say','-v',voice['voice'],'-r',str(voice['words_per_minute']),'-o',str(aiff),'-f',str(prompt)])
                run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}','-c','1',str(aiff),str(pcm)])
                data=read_pcm(pcm);assert audioop.max(data,2)>0;cache[key]=data
                prompt.unlink();aiff.unlink();pcm.unlink()
            return cache[key]
        def append(data,role,text=None,speaker=None,piece=None,question=None):
            nonlocal frame
            end=frame+len(data)//2
            segments.append(dict(role=role,text=text,speaker=speaker,piece=piece,question=question,
                                 repeat=1,start_frame=frame,end_frame=end,pcm_sha256=__import__('hashlib').sha256(data).hexdigest()))
            parts.append(data);frame=end
        def pause(seconds,role='silence',question=None):
            append(b'\0\0'*int(seconds*RATE),role,question=question)
        append(speech(draft['audio_introduction']),'introduction',draft['audio_introduction'],'N')
        pause(8)
        number=0
        for p,clip in enumerate(draft['clips'],1):
            nums=list(range(number+1,number+len(clip['questions'])+1))
            introduction=f'Questions {nums[0]} to {nums[-1]} are based on the following '+draft['material_noun']+'.'
            append(speech(introduction),'piece_announcement',introduction,'N',p);pause(1)
            for turn in clip['turns']:
                append(speech(turn['text'],turn['speaker']),'material',turn['text'],turn['speaker'],p)
                pause(.35)
            pause(1)
            for q in clip['questions']:
                number+=1;text=str(number)+'. '+q['spoken_question']
                append(speech(text),'spoken_question',text,'N',p,number)
                pause(draft['question_pause_seconds'],'answer_pause',number)
            pause(2)
        combined=scratch/'section.wav'
        with wave.open(str(combined),'wb')as stream:
            stream.setparams((1,2,RATE,0,'NONE','not compressed'))
            for data in parts:stream.writeframes(data)
        run(['afconvert','-f','m4af','-d','aac ','-b','64000',str(combined),str(target)])
        decoded=scratch/'decoded.wav'
        run(['afconvert','-f','WAVE','-d',f'LEI16@{RATE}','-c','1',str(target),str(decoded)])
        data=read_pcm(decoded);frames=len(data)//2;assert abs(frames-frame)<=4096 and audioop.max(data,2)>0
    spoken_segments=[s for s in segments if s['text']]
    track=dict(path=str(target.relative_to(REPO)),sha256=digest(target),bytes=target.stat().st_size,mime_type='audio/mp4',
               seconds=frames/RATE,response_numbers=list(range(1,number+1)),repeat_count=1,segments=segments,
               dialogue_words_once=sum(words(t['text'])for c in draft['clips']for t in c['turns']),
               spoken_question_words=sum(words(q['spoken_question'])for c in draft['clips']for q in c['questions']),
               spoken_words_with_instructions=sum(words(s['text'])for s in spoken_segments),
               decoded_frames=frames,pcm_frames_before_encoding=frame,peak_abs_sample=audioop.max(data,2),sample_rate=RATE)
    manifest=dict(version=version,id=draft['id'],manuscript=ref(manuscript),tracks=[track],voices=draft['speakers'],
                  source_contract=ref(BASE/draft['source_index']),source_group_id=source['id'],
                  question_pause_seconds=15,source_exact_pause_timing_not_independently_measured=True,
                  one_complete_section_not_one_clip_per_question=True,no_source_recording_reused=True,
                  whole_final_audio_decode_passed=True,temporary_PCM_not_retained=True,
                  independent_listening_pronunciation_prosody_student_commercial_production_validated=False)
    manifest_path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    return manifest_path


def compile_author(manuscript,manifest_path,output):
    manuscript, manifest_path, output = manuscript.resolve(), manifest_path.resolve(), output.resolve()
    draft=json.loads(manuscript.read_text());source_index,source=contract(draft);manifest=json.loads(manifest_path.read_text())
    assert manifest['manuscript']==ref(manuscript) and manifest['id']==draft['id']
    assert len(manifest['tracks'])==1;track=manifest['tracks'][0];asset=load_ref(track)
    assert track['repeat_count']==1 and track['decoded_frames']>0 and manifest['whole_final_audio_decode_passed']
    relative='../../../../'+asset.relative_to(REPO).as_posix()
    material='[完整本节音频（材料和问题均一遍，问题后留15秒作答）]('+relative+')'
    material+='\n\n'+ '\n\n'.join(f'第{i+1}段：第{1+sum(len(x["questions"])for x in draft["clips"][:i])}—{sum(len(x["questions"])for x in draft["clips"][:i+1])}题。'for i,c in enumerate(draft['clips']))
    tasks=[];teacher=[]
    for p,clip in enumerate(draft['clips'],1):
        teacher+=['### 第'+str(p)+'段完整原创脚本','\n\n'.join(t['speaker']+': '+t['text']for t in clip['turns'])]
        for q in clip['questions']:
            n=len(tasks)+1
            tasks.append(dict(number=n,stem=f'第{n}题（问题在录音中）',options=q['options'],answer=q['answer'],rationale=q['rationale']))
            teacher+=[f'### 第{n}题：'+q['answer'],'录音问题：'+q['spoken_question'],q['rationale']]
    teacher='\n\n'.join(teacher)
    notice='全部为原创虚构广播；配音为本机合成试听。具体篇数/响应数参照已核四级或六级转载题面，非官方原声或能力等值认证；15秒为本稿作答停顿，源录音逐次停顿未独立测量。未独立听辨/发音/自然语流/学生难度/商用/生产验证。'
    output.mkdir(parents=True,exist_ok=True);candidate=output/(draft['id']+'-v0.1.md');audit_path=output/(draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not audit_path.exists()
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+response_markdown(tasks)+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n\n'+notice+'\n')
    aud_asset={k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}
    audit=dict(version='0.1',id=draft['id'],grade=draft['grade'],questions=len(tasks),candidate_sha256=digest(candidate),
               canonical_response_block_sha256=__import__('hashlib').sha256(response_markdown(tasks).encode()).hexdigest(),
               review_response_tasks=tasks,source_index=ref(source_index),source_group_id=source['id'],
               source_observation=dict(source_responses=source['responses'],source_reuse_rule=source['reuse_rule'],source_material=source['material'],source_candidates=source['candidates']),
               manuscript=ref(manuscript),audio_generation=ref(manifest_path),audio_assets=[aud_asset],student_passage=material,
               body_load_text='\n\n'.join(material.split('\n\n')[1:]),original_transcript_sections=draft['clips'],
               audio_transcript_in_teacher_only=True,spoken_questions_in_teacher_only=True,
               author_answer_vector=[q['answer']for q in tasks],source_original_key_not_gold=True,
               questions_per_extract=[len(c['questions'])for c in draft['clips']],extracts=len(draft['clips']),
               source_level_equivalence_established=False,authored_student_inputs_complete=True,fictional_content_not_empirical_fact_gold=True,
               synthetic_audio_not_natural_listening_calibration=True,independent_teacher_student_commercial_production_validated=False,
               load_measure=dict(body_English_words=words('\n\n'.join(material.split('\n\n')[1:])),stem_English_words=sum(words(q['stem'])for q in tasks),
                                 options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),
                                 audio_dialogue_English_words_once=track['dialogue_words_once'],audio_question_English_words_once=track['spoken_question_words'],
                                 audio_spoken_words_including_repetition_and_introductions=track['spoken_words_with_instructions'],
                                 audio_seconds_including_repetition_and_pauses=track['seconds'],artifact_URLs_excluded_from_reading_load=True,
                                 output_response_positions=len(tasks),output_mode='closed_letter_selection'))
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade=draft['grade'],family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=len(tasks),
                candidate=ref(candidate),author_check=ref(audit_path),source_index=ref(source_index),source_group_ids=[source['id']],anchor_group_ids=[source['id']],
                instruction=draft['instruction'],source_form_notice=draft['source_form_notice'])


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--manuscript',action='append',type=Path,required=True)
    parser.add_argument('--audio-dir',type=Path,default=REPO/'build/english-benchmark-authority-20261017/original-audio')
    parser.add_argument('--output',type=Path,default=BASE/'AuthorityGap20261017/Authored');parser.add_argument('--version',default='0.1')
    parser.add_argument('--metadata-output',type=Path,required=True);args=parser.parse_args();assert not args.metadata_output.exists()
    rows=[]
    for manuscript in args.manuscript:
        manifest=render(manuscript,args.audio_dir,args.version);rows.append(compile_author(manuscript,manifest,args.output));print(rows[-1]['id'],flush=True)
    args.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
