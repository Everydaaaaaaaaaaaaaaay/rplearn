#!/usr/bin/env python3
"""Primary dialogue groups keep printed choices and unknown source playback rules."""
import argparse
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def check(group, audit, binding, source):
    selected = json.loads(load_ref(source['selected_native']).read_text())
    assert selected['source'] == source['source'] and selected['source_images'] == source['source_images']
    assert selected['subgroups'] == [[16], [17,18], [19,20]]
    assert list(map(int, selected['printed_choices'])) == source['source_question_numbers'] == list(range(16,21))
    assert all(len(v) == 3 for v in selected['printed_choices'].values())
    assert selected['script_audio_key_absent_from_selected_scan'] and selected['repeats_and_timing_not_printed']
    assert not source['source_key_acquired'] and not source['source_script_acquired'] and not source['source_original_audio_acquired'] and not source['source_full_input_verified']
    assert source['features']['repeats'] is None and source['features']['preview_seconds'] is None and source['features']['answer_seconds'] is None
    draft = json.loads(load_ref(audit['manuscript']).read_text()); generation = json.loads(load_ref(audit['audio_generation']).read_text())
    assert draft['grade'] == group['grade'] == binding['level'] == source['level'] == 'primary6'
    assert draft['source_group_id'] == source['id'] and draft['source_questions_per_clip'] == source['features']['subgroup_responses'] == [1,2,2]
    assert draft['source_replay_rule'] == 'not_printed' and draft['render_repeat_count'] == 1
    assert generation['manuscript'] == audit['manuscript'] and generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
    assert len(draft['clips']) == len(generation['tracks']) == len(audit['audio_assets']) == len(group['requiredAudioAssets']) == source['materials'] == 3
    assert len(group['questions']) == source['responses'] == binding['responses'] == 5
    cursor = 1
    for clip, track, asset, shown in zip(draft['clips'], generation['tracks'], audit['audio_assets'], group['requiredAudioAssets']):
        numbers = list(range(cursor, cursor+len(clip['questions'])))
        assert set(t['speaker'] for t in clip['turns']) == {'M','W'}
        assert track['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == numbers
        assert track['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == 1
        assert track['sha256'] == asset['sha256'] == shown['asset']['sha256']; load_ref(asset)
        heard = [s for s in track['segments'] if s['role'] == 'dialogue']
        assert [(s['speaker'],s['text'],s['repeat'])for s in heard] == [(t['speaker'],t['text'],1)for t in clip['turns']]
        assert not any(s['role']=='repeat_instruction'for s in track['segments'])
        for segment in [track['segments'][1], track['segments'][-1]]:
            assert segment['role']=='silence' and segment['end_frame']-segment['start_frame']==5*len(numbers)*track['sample_rate']
        assert track['decoded_frames']>0 and track['peak_abs_sample']>0
        for n,q in zip(numbers,clip['questions']):assert group['questions'][n-1]==dict(number=n,**q) and [k for k,_ in q['options']]==['A','B','C']
        for t in clip['turns']:assert t['text']in group['reviewText']and t['text']not in group['passageHtml']
        cursor+=len(numbers)
    assert audit['source_timing_unknown_preserved'] and audit['audio_transcript_in_teacher_only'] and audit['primary_dialogue_listening']
    return True


def compile_author(manuscript,version='0.1'):
    manuscript=manuscript.resolve();draft=json.loads(manuscript.read_text());bp=load_ref(draft['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==draft['source_binding'])
    manifest=REPO/'build/english-benchmark-authority-20261017/original-audio'/(draft['id']+'-audio-v'+version+'.json');generation=json.loads(manifest.read_text());assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    material=[];teacher=[];tasks=[];assets=[]
    for i,(clip,track)in enumerate(zip(draft['clips'],generation['tracks']),1):
        p=load_ref(track);ns=track['response_numbers'];label='对话'+str(i)+'（第'+'、'.join(map(str,ns))+'题；本机一遍，可重播）'
        material+=['### 材料'+str(i),'['+label+'](../../../../'+str(p.relative_to(REPO))+')'];tasks += [dict(number=n,**q)for n,q in zip(ns,clip['questions'])];assets.append({k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']});teacher+=['### 对话'+str(i)+'完整原创脚本','\n\n'.join(t['speaker']+': '+t['text']for t in clip['turns'])]
    teacher += ['来源为东城区2024—2025第一学期小六公开试卷扫描第三大题，三对话分别1/2/2，共5题三选；源题16—20仅局部归一为1—5，完整大题不截六题。正文有区/年级/学期，不从区名补省级字段；原学校未认证。', '原卷此处没有重播次数、读题/作答秒数或逐题分值，音频/脚本/键均未取得，不从候选推导源答案。本机每段一遍、听前后每题5秒属于作者演示安排，可重播，非来源强制规则。完整原创输入齐备不等来源全输入或gold；自然语流、目标难度、独立教研、学生、商用、生产均未验证。']
    body='\n\n'.join(material);block=response_markdown(tasks);p=manuscript.parent/(draft['id']+'-v'+version+'.md');ap=manuscript.parent/(draft['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    audit=dict(version=version,id=draft['id'],grade='primary6',questions=5,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=draft['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=assets,audio_transcript_in_teacher_only=True,primary_dialogue_listening=True,source_timing_unknown_preserved=True,load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in generation['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in generation['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in generation['tracks']),artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade='primary6',family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[draft['source_group_id']],instruction=draft['instruction'],source_form_notice='小六普通卷三对话1/2/2五题三选已核；源音频/脚本/键缺，遍数与停顿未印。本稿完整原创音频/题面/依据；本机一遍和停顿不冒来源要求。',format_summary='3对话 / 1+2+2共5回应 / 每题三选 / 源遍数时序未知 / 本机每段一遍可重播')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists();rows=[compile_author(m)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=5*len(rows)))
