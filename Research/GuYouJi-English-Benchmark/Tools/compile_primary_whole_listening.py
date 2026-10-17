#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Five-slot letter dictation and whole five-question dialogue retain three passes."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def filled(context, tasks, overrides=None):
    result=context
    for q in tasks:
        result=result.replace('('+str(q['number'])+') ____',(overrides or {}).get(q['number'],q['acceptedAnswers'][0]))
    return result


def check(group,audit,binding,source):
    selected=json.loads(load_ref(source['selected_native']).read_text());raw=load_ref(selected['source_native']).read_text();assert selected['source_HTML']==source['source']
    for name in ['student_span','script_and_key_span']:
        span=selected[name];assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest()==span['sha256']
    student=raw[selected['student_span']['start']:selected['student_span']['end']];keyview=raw[selected['script_and_key_span']['start']:selected['script_and_key_span']['end']]
    assert '三遍'in student and selected['repeat_count']==source['features']['repeat_count']==3
    assert not source['source_original_audio_acquired']and not source['source_full_input_verified']and source['source_original_key_not_gold']
    assert source['region_body_unknown']and not source['original_school_authenticated']
    isfill=source['kind']=='listening_passage_completion'
    assert selected['reference_keys']==(re.findall(r'3[1-5]\.([A-Za-z]+)',keyview)if isfill else list(re.search(r'答案：36-40\s+([ABC]{5})',keyview)[1]))
    assert selected['question_numbers']==source['source_question_numbers']==list(range(31,36)if isfill else range(36,41))
    d=json.loads(load_ref(audit['manuscript']).read_text());generation=json.loads(load_ref(audit['audio_generation']).read_text());clip=d['clips'][0];track=generation['tracks'][0];asset=audit['audio_assets'][0];display=group['requiredAudioAssets'][0]
    assert generation['manuscript']==audit['manuscript']and generation['whole_final_audio_decode_passed']and generation['no_source_recording_reused']
    assert d['source_group_id']==source['id']and d['grade']==group['grade']=='primary5'and d['source_repeat_count']==3
    assert len(d['clips'])==len(generation['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==1
    assert len(clip['questions'])==len(group['questions'])==source['responses']==binding['responses']==5
    assert track['response_numbers']==asset['response_numbers']==display['response_numbers']==list(range(1,6))and track['repeat_count']==display['repeat_count']==3
    assert track['sha256']==asset['sha256']==display['asset']['sha256'];load_ref(asset)
    heard=[s for s in track['segments']if s['role']=='dialogue'];assert [(s['speaker'],s['text'],s['repeat'])for s in heard]==[(t['speaker'],t['text'],r)for r in [1,2,3]for t in clip['turns']]
    assert len([s for s in track['segments']if s['role']=='repeat_instruction'])==2
    assert track['decoded_frames']>0 and track['peak_abs_sample']>0
    for segment in [track['segments'][1],track['segments'][-1]]:assert segment['role']=='silence'and segment['end_frame']-segment['start_frame']==25*track['sample_rate']
    assert all(group['questions'][n-1]==dict(number=n,**q)for n,q in enumerate(clip['questions'],1))
    assert track['spoken_words_with_instructions']==3*sum(words(t['text'])for t in clip['turns'])+sum(words(s['text'])for s in track['segments']if s['role']in {'introduction','repeat_instruction'})
    if isfill:
        assert len(clip['turns'])==1 and clip['turns'][0]['speaker']=='N'
        assert filled(clip['context'],group['questions'])==clip['turns'][0]['text']==audit['canonical_filled_letter']
        assert re.findall(r'\((\d+)\) ____',clip['context'])==list(map(str,range(1,6)))
        for q in group['questions']:
            assert not q['options']and q['fillMarking']['normalization']=='english_phrase_v1'and q['fillMarking']['maxWords']is None and q['fillMarking']['unlisted']=='review'
            assert all('____'not in filled(clip['context'],group['questions'],{q['number']:v})for v in q['acceptedAnswers'])
        assert audit['full_variant_combinations']==__import__('math').prod(len(q['acceptedAnswers'])for q in group['questions'])
    else:
        assert set(t['speaker']for t in clip['turns'])=={'M','W'}and all(len(q['options'])==3 for q in group['questions'])
        assert selected['teacher_part7_calls_shortpassage_but_student_and_AB_script_dialogue']
    for t in clip['turns']:assert t['text']in group['reviewText']and t['text']not in group['passageHtml']
    assert audit['primary_whole_listening']and audit['audio_transcript_in_teacher_only']
    return True


def compile_author(manuscript,version='0.1'):
    manuscript=manuscript.resolve();d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding'])
    mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+version+'.json');generation=json.loads(mp.read_text());assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    clip=d['clips'][0];track=generation['tracks'][0];audio=load_ref(track);tasks=[dict(number=n,**q)for n,q in enumerate(clip['questions'],1)];isfill=d['family']=='listening_passage_completion'
    material=(clip['context']+'\n\n'if clip['context']else'')+'[完整五题音频（三遍）](../../../../'+str(audio.relative_to(REPO))+')';block=response_markdown(tasks)
    teacher='\n\n'.join('第'+str(n)+'空全篇可接受回填：\n\n'+filled(clip['context'],tasks,{n:v})for n,q in enumerate(tasks,1)for v in q['acceptedAnswers'])if isfill else''
    teacher+='\n\n### 完整原创脚本\n\n'+'\n\n'.join(t['speaker']+': '+t['text']for t in clip['turns'])
    teacher+='\n\n来源为小五下期公开质量检测同卷完整第六/七大题，五空同一封信或一完整双人对话五题三选，均听三遍/每题1分共5分。地域仅公开标题，原学校/施测未认证，原音轨缺；源参考键非gold。第七题教参称短文、学生指令与A/B脚本为对话，角色按实际脚本保留，不默改该标签冲突。\n\n本机听前/最后25秒、每次中间一秒与重播提示为演示编排，不当来源精确时序。未给词库，不附数字限词；听写按实际听词和已核英美拼写核对，未列形式待复核，不做语义近似判分。源事实内容不迁移；完整原创与本机检查不代表自然听辨/难度、独立教研、学生、商用或生产验证。\n'
    p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher)
    asset={k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}
    audit=dict(version=version,id=d['id'],grade='primary5',questions=5,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=material,body_load_text=clip['context'],manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=[asset],audio_transcript_in_teacher_only=True,primary_whole_listening=True,source_timing_unknown_preserved=True,load_measure=dict(body_English_words=words(clip['context']),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds'],artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    if isfill:audit.update(canonical_filled_letter=filled(clip['context'],tasks),full_variant_combinations=__import__('math').prod(len(q['acceptedAnswers'])for q in tasks),accepted_outputs_not_capped_at_three=True)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label=d['family_label'],title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice='小五同卷完整书信五空或整对话五题三选/三遍结构已核；源题面/脚本/键视图在库，原音轨缺。完整原创可测试，非源全输入/独立听校或学生难度校准。',format_summary='1完整书信 / 5空无词库 / 3遍 / 已核拼写变体同等接受 / 不另加数字限词'if isfill else'1完整双人对话 / 5题各三选 / 3遍 / 不替代三对话1+2+2')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists();rows=[compile_author(m)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=5*len(rows)))
