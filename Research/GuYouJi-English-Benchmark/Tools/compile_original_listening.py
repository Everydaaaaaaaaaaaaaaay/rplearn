#!/usr/bin/env python3
"""Compile owned listening manuscripts and verified audio into full review authors."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown


def ref(path):
    return {'path':str(path.relative_to(BASE)) if path.is_relative_to(BASE) else str(path.relative_to(REPO)),
            'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?",text))


def compile_author(manuscript, manifest_path, output):
    manuscript=manuscript.resolve(); manifest_path=manifest_path.resolve(); output=output.resolve()
    draft=json.loads(manuscript.read_text());manifest=json.loads(manifest_path.read_text())
    assert manifest['manuscript']==ref(manuscript) and manifest['id']==draft['id']
    source_index=BASE/draft['source_index'];sources=json.loads(source_index.read_text())['groups']
    source=next(s for s in sources if s['id']==draft['source_group_id'])
    family=draft['family']
    assert source['kind']==family
    assert family in {'listening_extract_choice','listening_interview_choice','listening_double_matching'}
    assert source['level']==draft['grade']=='advanced'
    assert len(manifest['tracks'])==len(draft['clips'])==(3 if family=='listening_extract_choice' else 1)
    if family=='listening_extract_choice':
        assert source['material']['extracts']==3
    elif family=='listening_interview_choice':
        assert source['material']['interview']==1 and source['material']['interviewees']==2
        assert set(t['speaker'] for t in draft['clips'][0]['turns'])=={'I','G1','G2'}
    else:
        assert source['material']['monologues']==5 and source['material']['two_tasks_for_same_five_speakers_not_two_independent_groups']
        assert [t['speaker'] for t in draft['clips'][0]['turns']]==['S1','S2','S3','S4','S5']
        assert len(draft['banks'])==2 and all(len(b['options'])==8 for b in draft['banks'])
    tasks=[];material=[];teacher=[];assets=[]
    for n,(clip,track) in enumerate(zip(draft['clips'],manifest['tracks']),1):
        response_numbers=([2*n-1,2*n] if family=='listening_extract_choice' else list(range(1,source['responses']+1)))
        assert track['response_numbers']==response_numbers and track['repeat_count']==2
        assert track['decoded_frames']>0 and track['peak_abs_sample']>0
        for repeat in [1,2]:
            segments=[s for s in track['segments'] if s['role']=='dialogue' and s['repeat']==repeat]
            assert [(s['speaker'],s['text']) for s in segments]==[(t['speaker'],t['text']) for t in clip['turns']]
        path=load_ref(track)
        relative='../../../../'+path.relative_to(REPO).as_posix()
        label=f'音频{n}（第{response_numbers[0]}—{response_numbers[-1]}题；内含两遍）'
        material += [f'### '+(f'Extract {n}' if family=='listening_extract_choice' else draft['family_label']),clip['context'],f'[{label}]({relative})']
        if family=='listening_double_matching':
            for bank in draft['banks']:
                material += ['### '+bank['title'],bank['instruction'],'\n\n'.join(k+'. '+v for k,v in bank['options'])]
        teacher += [f'### 音频{n}完整原创脚本','\n\n'.join(t['speaker']+': '+t['text'] for t in clip['turns'])]
        assets.append({k:track[k] for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']})
        for question in clip['questions']:
            number=len(tasks)+1
            assert len(question['options'])==source['candidates']['per_response'][number-1] and question['answer'] in dict(question['options'])
            if family=='listening_double_matching':
                assert question['options']==draft['banks'][(number-1)//5]['options']
            tasks.append(dict(number=number,**question))
    assert len(tasks)==source['responses']
    student_material='\n\n'.join(material)
    body_load_text='\n\n'.join(row for row in material if not row.startswith('['))
    output.mkdir(parents=True,exist_ok=True)
    candidate=output/(draft['id']+'-v0.1.md');audit_path=output/(draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not audit_path.exists()
    reasons='\n\n'.join('### '+str(q['number'])+'：'+q['answer']+'\n\n'+q['rationale'] for q in tasks)
    teacher='\n\n'.join(teacher)
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+student_material+
                         '\n\n<!-- responses:start -->\n\n'+response_markdown(tasks)+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+reasons+'\n\n'+teacher+
                         '\n\n配音为本机合成试听，未做自然语流、发音或目标学生难度标定；不是源考试原录音。全部材料为原创虚构内容，参照C1完整形式不等于产品高级档与C1等值。作者自审不等独立教研、学生、商用或生产验收。\n')
    audit=dict(version='0.1',id=draft['id'],grade=draft['grade'],questions=len(tasks),candidate_sha256=ref(candidate)['sha256'],
               canonical_response_block_sha256=hashlib.sha256(response_markdown(tasks).encode()).hexdigest(),review_response_tasks=tasks,
               source_index=ref(source_index),source_group_id=source['id'],source_observation={'source_responses':source['responses'],'source_reuse_rule':source['reuse_rule'],'source_material':source['material'],'source_candidates':source['candidates']},
               manuscript=ref(manuscript),audio_generation=ref(manifest_path),audio_assets=assets,student_passage=student_material,body_load_text=body_load_text,
               original_transcript_sections=draft['clips'],audio_transcript_in_teacher_only=True,
               author_answer_vector=[q['answer'] for q in tasks],
               load_measure={'body_English_words':words(body_load_text),'stem_English_words':sum(words(q['stem']) for q in tasks),'options_English_words_with_repeated_bank':sum(words(v) for q in tasks for _,v in q['options']),
                             'audio_dialogue_English_words_once':sum(t['dialogue_words_once'] for t in manifest['tracks']),
                             'audio_spoken_words_including_repetition_and_introductions':sum(t['spoken_words_with_instructions'] for t in manifest['tracks']),
                             'audio_seconds_including_repetition_and_pauses':sum(t['seconds'] for t in manifest['tracks']),
                             'artifact_URLs_excluded_from_reading_load':True,'output_response_positions':len(tasks),'output_mode':'closed_letter_selection'},
               extracts=len(draft['clips']),questions_per_extract=[len(c['questions']) for c in draft['clips']],source_original_key_not_gold=True,source_level_equivalence_established=False,
               fictional_content_not_empirical_fact_gold=True,authored_student_inputs_complete=True,
               independent_teacher_student_commercial_production_validated=False,synthetic_audio_not_natural_listening_calibration=True)
    if family=='listening_double_matching':
        audit.update(shared_banks=draft['banks'],same_five_speakers_for_both_tasks=True,two_tasks_one_whole_group=True,
                     no_unprinted_once_rule_added=True)
        audit['load_measure']['options_English_words_unique_shared_banks']=sum(words(v) for b in draft['banks'] for _,v in b['options'])
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    notice={'listening_extract_choice':'三段/每段两题三选','listening_interview_choice':'一访谈者与两嘉宾/六题四选',
            'listening_double_matching':'同五独白/两个独立八项库/共十回应的一完整组'}[family]
    return dict(id=draft['id'],grade=draft['grade'],family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=len(tasks),
                candidate=ref(candidate),author_check=ref(audit_path),source_index=ref(source_index),source_group_ids=[source['id']],anchor_group_ids=[source['id']],
                instruction=draft['instruction'],source_form_notice='高级形式参照已核官方C1样卷'+notice+'；配音为本机合成试听，未做自然语流或目标学生难度标定，不代表产品高级档与C1等值。')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manuscript',action='append',type=Path,required=True)
    parser.add_argument('--audio-dir',type=Path,default=REPO/'build/english-benchmark-authority-20261017/original-audio')
    parser.add_argument('--audio-version',default='0.1')
    parser.add_argument('--output',type=Path,default=BASE/'AuthorityGap20261017/Authored')
    parser.add_argument('--metadata-output',type=Path,required=True)
    args=parser.parse_args();assert not args.metadata_output.exists()
    rows=[]
    for p in args.manuscript:
        draft=json.loads(p.read_text());rows.append(compile_author(p,args.audio_dir/(draft['id']+f'-audio-v{args.audio_version}.json'),args.output))
    args.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'groups':len(rows),'responses':sum(r['questions'] for r in rows)}))
