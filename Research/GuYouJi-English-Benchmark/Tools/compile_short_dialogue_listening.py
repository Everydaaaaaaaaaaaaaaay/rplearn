#!/usr/bin/env python3
"""Keep all five short-dialogue items, media, printed questions and source limits."""
import argparse
import hashlib
import html
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words


def ref(p):
    p=p.resolve()
    return dict(path=str(p.relative_to(BASE))if p.is_relative_to(BASE)else str(p.relative_to(REPO)),sha256=hashlib.sha256(p.read_bytes()).hexdigest())


def check(group,audit,binding,source):
    selected=json.loads(load_ref(source['selected_native']).read_text())
    assert selected['whole_first_section']and source['whole_first_section']
    assert selected['source_instruction_summary']==source['features']==dict(conversations=5,responses=5,options_per_response=3,letters=['A','B','C'],repeats=1,after_each_seconds=10,points_each=1.5,section_points=7.5)
    assert selected['original_audio']==source['original_audio_assets'][0]
    assert selected['official_key']==source['key_reference']
    assert selected['question_image']==source['source_images'][0]
    raw=html.unescape(load_ref(selected['public_question_HTML']).read_text())
    assert '每段对话仅读一遍'in raw and '10秒钟'in raw
    key=json.loads(load_ref(selected['key_view']).read_text())
    assert key['source_sha256']==selected['official_key']['sha256']
    assert key['published_reference_keys']==['B','C','B','A','B']and key['question_numbers']==[1,2,3,4,5]
    assert not key['source_full_transcript_verified']and not source['source_full_transcript_verified']
    assert selected['old_partial_ASR_not_upgraded']and not source['source_audio_independent_aural_review']
    draft=json.loads(load_ref(audit['manuscript']).read_text());generation=json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript']==audit['manuscript']and generation['whole_final_audio_decode_passed']and generation['no_source_recording_reused']
    assert draft['source_group_id']==source['id']and draft['grade']==group['grade']==10
    assert len(draft['clips'])==len(generation['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==5
    assert len(group['questions'])==binding['responses']==source['responses']==5
    for n,(clip,track,asset,shown,q)in enumerate(zip(draft['clips'],generation['tracks'],audit['audio_assets'],group['requiredAudioAssets'],group['questions']),1):
        assert len(clip['questions'])==1 and set(t['speaker']for t in clip['turns'])=={'M','W'}
        assert clip['preview_seconds']==0 and clip['answer_seconds']==10
        assert track['response_numbers']==asset['response_numbers']==shown['response_numbers']==[n]
        assert track['repeat_count']==asset['repeat_count']==shown['repeat_count']==1
        assert track['sha256']==asset['sha256']==shown['asset']['sha256']
        assert track['sha256']not in {a['sha256']for a in source['original_audio_assets']}
        load_ref(asset)
        heard=[s for s in track['segments']if s['role']=='dialogue']
        assert [(s['speaker'],s['text'])for s in heard]==[(t['speaker'],t['text'])for t in clip['turns']]
        assert all(s['repeat']==1 for s in heard)and not any(s['role']=='repeat_instruction'for s in track['segments'])
        last=track['segments'][-1];assert last['role']=='silence'and last['end_frame']-last['start_frame']==10*track['sample_rate']
        assert track['decoded_frames']>0 and track['peak_abs_sample']>0
        assert track['dialogue_words_once']==sum(words(t['text'])for t in clip['turns'])
        assert track['spoken_words_with_instructions']==track['dialogue_words_once']+words('Text '+str(n))
        assert q==dict(number=n,**clip['questions'][0])and [k for k,_ in q['options']]==['A','B','C']
        for turn in clip['turns']:assert turn['text']in group['reviewText']and turn['text']not in group['passageHtml']
    assert audit['audio_transcript_in_teacher_only']and audit['source_script_pending_not_hidden']
    return True


def compile_author(manuscript,version='0.1',audio_version='0.1'):
    manuscript=manuscript.resolve();draft=json.loads(manuscript.read_text())
    manifest=REPO/'build/english-benchmark-authority-20261017/original-audio'/(draft['id']+'-audio-v'+audio_version+'.json');generation=json.loads(manifest.read_text())
    assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    bp=load_ref(draft['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==draft['source_binding'])
    material=[];teacher=[];tasks=[];assets=[]
    for n,(clip,track)in enumerate(zip(draft['clips'],generation['tracks']),1):
        audio=load_ref(track)
        material+=['### 对话'+str(n),'[对话'+str(n)+'（第'+str(n)+'题；一遍，末尾10秒）](../../../../'+str(audio.relative_to(REPO))+')']
        tasks.append(dict(number=n,**clip['questions'][0]));assets.append({k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']})
        teacher+=['### 对话'+str(n)+'完整原创脚本','\n\n'.join(t['speaker']+': '+t['text']for t in clip['turns'])]
    teacher+='来源第一节每题1.5分、五题7.5分是该源卷的计分配置，非年级统一标准。五段全保留，题干与候选在页面印出，音轨不另朗读题目和选项；每段一遍，末尾十秒。审阅可重播，非正式考试播放次数控制。原卷题面、官方键与原录音在库，但源脚本仍未完整核证，旧片段ASR不升为gold。本稿所有对话、题目、候选与逐项依据为完整原创；本机合成试听，不证明自然语流、难度、独立教研、学生、商用或生产通过。'.split('\n')
    body='\n\n'.join(material);block=response_markdown(tasks);p=manuscript.parent/(draft['id']+'-v'+version+'.md');ap=manuscript.parent/(draft['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    a=dict(version=version,id=draft['id'],grade=10,questions=5,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=draft['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=assets,audio_transcript_in_teacher_only=True,short_dialogue_listening=True,source_script_pending_not_hidden=True,load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in generation['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in generation['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in generation['tracks']),artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade=10,family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[draft['source_group_id']],instruction=draft['instruction'],source_form_notice='普通高一期末卷第一节五短对话结构已核；原题面/官方键/原录音在库，源脚本仍未完整核证，不当gold。本稿五段完整原创配音、题面和依据可审阅；非独立难度或正式施测验证。',format_summary='5独立短对话 / 每段1题三选 / 共5回应 / 每段1遍 / 听后10秒 / 印出题干与候选')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);p.add_argument('--version',default='0.1');p.add_argument('--audio-version',default='0.1');a=p.parse_args();assert not a.metadata_output.exists()
    rows=[compile_author(m,a.version,a.audio_version)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=sum(m['questions']for m in rows)))
