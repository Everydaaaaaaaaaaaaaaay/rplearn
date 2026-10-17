#!/usr/bin/env python3
"""Compile whole school listening activities without inventing exam conditions."""
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words


def ref(path):
    path=path.resolve()
    return dict(path=str(path.relative_to(BASE))if path.is_relative_to(BASE)else str(path.relative_to(REPO)),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def check(group,audit,binding,source):
    selected=json.loads(load_ref(source['selected_native']).read_text())
    assert selected['source_question_image']==source['source_images'][0]
    assert selected['source_script_image']==source['source_images'][1]
    assert selected['source_audio']==source['original_audio_assets'][0]
    assert selected['derived_reference_keys']==['T','F','T','F']
    assert not selected['publisher_key_acquired'] and not source['publisher_key_acquired']
    assert source['source_kind']=='publisher_curricular_activity_not_school_exam'
    assert source['features']['printed_replay_rule']==selected['replay_rule_in_printed_instruction']=='not_explicit'
    assert len(selected['statements'])==source['responses']==binding['responses']==4
    script=json.loads(load_ref(selected['script_transcription']).read_text())
    assert selected['script']==next(b for b in script['blocks']if b['label']=='Section A, 1c')
    assert len({t['speaker']for t in selected['script']['turns']})==3
    draft=json.loads(load_ref(audit['manuscript']).read_text())
    generation=json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript']==audit['manuscript'] and generation['whole_final_audio_decode_passed']
    assert generation['no_source_recording_reused'] and draft['source_group_id']==source['id']
    assert draft['source_replay_rule']=='not_explicit' and draft['render_repeat_count']==1
    assert len(draft['clips'])==len(generation['tracks'])==len(group['requiredAudioAssets'])==1
    clip=draft['clips'][0];track=generation['tracks'][0]
    assert track['response_numbers']==audit['audio_assets'][0]['response_numbers']==group['requiredAudioAssets'][0]['response_numbers']==[1,2,3,4]
    assert track['repeat_count']==audit['audio_assets'][0]['repeat_count']==group['requiredAudioAssets'][0]['repeat_count']==1
    assert len({t['speaker']for t in clip['turns']})==3 and clip['preview_seconds']==0
    heard=[s for s in track['segments']if s['role']=='dialogue']
    assert [(s['speaker'],s['text'])for s in heard]==[(t['speaker'],t['text'])for t in clip['turns']]
    assert all(s['repeat']==1 for s in heard) and track['repeat_count']==1
    assert not any(s['role']=='repeat_instruction'for s in track['segments'])
    assert track['decoded_frames']>0 and track['peak_abs_sample']>0
    assert track['sha256']not in {a['sha256']for a in source['original_audio_assets']}
    load_ref(audit['audio_assets'][0])
    for turn in clip['turns']:
        assert turn['text']in group['reviewText'] and turn['text']not in group['passageHtml']
    assert audit['audio_transcript_in_teacher_only']
    assert track['dialogue_words_once']==sum(words(t['text'])for t in clip['turns'])
    assert track['spoken_words_with_instructions']==track['dialogue_words_once']+words(draft['audio_introduction'])
    assert all(q['options']==[['T','正确'],['F','错误']]and q['answer']in ['T','F']for q in group['questions'])
    assert [dict(number=i+1,**q)for i,q in enumerate(clip['questions'])]==group['questions']
    return True


def compile_author(manuscript,version='0.1',audio_version='0.1'):
    manuscript=manuscript.resolve();draft=json.loads(manuscript.read_text())
    manifest=REPO/'build/english-benchmark-authority-20261017/original-audio'/(draft['id']+'-audio-v'+audio_version+'.json')
    generation=json.loads(manifest.read_text());assert generation['manuscript']==ref(manuscript)
    binding_path=load_ref(draft['source_bindings']);binding=next(b for b in json.loads(binding_path.read_text())['bindings']if b['id']==draft['source_binding'])
    track=generation['tracks'][0];audio=load_ref(track);clip=draft['clips'][0]
    tasks=[dict(number=n+1,**q)for n,q in enumerate(clip['questions'])]
    material=clip['context']+'\n\n[完整对话音频（四题；音轨内一遍，可自行重播）](../../../../'+str(audio.relative_to(REPO))+')'
    teacher='### 完整原创对话脚本\n\n'+'\n\n'.join(t['speaker']+': '+t['text']for t in clip['turns'])
    teacher+='\n\n每个陈述1分，共4个回应，按整段对话判断，不用现实常识替代录音。来源是教材活动：相邻开放问答与口语活动不拼入本组，来源无统一重播次数或限时明文；本机音轨内一遍、自主重播仅为审阅安排。三人分声部合成是本机试听，不代表自然语流、听辨难度或正式施测。脚本仅解析可见，人物与事件虚构。原题参考为研究者按印本脚本推导，不是已取得官方键；独立教研、学生、商用、生产未验证。\n'
    candidate=manuscript.parent/(draft['id']+'-v'+version+'.md');audit_path=manuscript.parent/(draft['id']+'-author-check-v'+version+'.json')
    assert not candidate.exists()and not audit_path.exists()
    block=response_markdown(tasks)
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher)
    audit=dict(version=version,id=draft['id'],grade=7,questions=4,candidate_sha256=ref(candidate)['sha256'],source_binding=binding['id'],source_bindings=ref(binding_path),source_group_id=draft['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=material,body_load_text=clip['context'],manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=[{k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}],audio_transcript_in_teacher_only=True,publisher_listening_true_false=True,load_measure=dict(body_English_words=words(clip['context']),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=0,output_response_positions=4,audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds'],artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade=7,family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=4,candidate=ref(candidate),author_check=ref(audit_path),source_group_ids=[draft['source_group_id']],instruction=draft['instruction'],source_form_notice='人教版初一下册教材活动参照，不当普通考试认证。题面/印本脚本/原录音均已存，源键是研究者推导、不是官方键；本稿完整原创对话和本机配音。',format_summary='1对话 / 3参与者 / 4陈述 / T或F / 来源重播规则未明 / 本机音轨1遍可重播')


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);p.add_argument('--version',default='0.1');p.add_argument('--audio-version',default='0.1');a=p.parse_args();assert not a.metadata_output.exists()
    rows=[compile_author(m,a.version,a.audio_version)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=sum(r['questions']for r in rows)))
