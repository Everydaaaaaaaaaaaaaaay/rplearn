#!/usr/bin/env python3
"""Whole junior sections with exact concrete sources and visible companion gaps."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import REPO, load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from junior_listening_contract import validate_draft
from render_original_listening import words


def check(group, audit, binding, source):
    selected = json.loads(load_ref(source['selected_native']).read_text())
    raw = load_ref(selected['source']).read_text()
    for span in selected['spans']:
        assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest() == span['sha256']
    if source['id'] == 'grade7-huangshan2026-21cnjy25150014.listening.sectionI':
        student=next(s for s in selected['spans'] if s['role']=='whole_first_section')
        student_text=raw[student['start']:student['end']]
        key_span=next(s for s in selected['spans'] if s['role']=='published_key')
        assert '1-5. BACAC' in raw[key_span['start']:key_span['end']]
        assert '每段对话读两遍' in student_text and selected['reference_keys']==list('BACAC')
        assert len(re.findall(r'\n[1-5]\. ',student_text))==5
        assert all(len(re.findall(r'\b'+k+r'\. ',student_text))==5 for k in 'ABC')
        assert source['features']['candidate_media']=='all_printed_text'
        assert not source['features']['source_actual_speaker_roles_verified']
        assert source['features']['roles_are_owned_rendering_not_source_gender_claim']
        assert not selected['source_script_acquired'] and selected['source_full_printed_input_verified']
        assert source['features']['source_timing_not_printed']
        assert source['features']['preview_seconds_per_question'] is None and source['features']['answer_seconds_per_question'] is None
    elif source['level'] == 7:
        key_span=next(s for s in selected['spans'] if s['role']=='published_key_and_complete_printed_script')
        key_text=raw[key_span['start']:key_span['end']]
        if source['kind']=='listening_table_completion':
            keys={int(n):v.split('##') for n,v in re.findall(r'(1[6-9]|20)\.\s*(\S+)',key_text)}
        else:
            keys={int(n):k for n,k in re.findall(r'(\d+)\.\s*([ABC])',key_text)}
        assert selected['reference_keys']==[keys[n] for n in selected['source_question_numbers']]
        assert selected['source_full_printed_input_verified'] and not selected['whole_original_paper_layout_verified']
        assert source['features']['source_timing_not_printed']
        assert source['features']['preview_seconds_per_question'] is None and source['features']['answer_seconds_per_question'] is None
    elif source['level'] == 8:
        key_span=next(s for s in selected['spans'] if s['role']=='published_key_including_conflicting_header')
        keys={int(n):k for n,k in re.findall(r'(\d+)\.\s*([ABC])',raw[key_span['start']:key_span['end']])}
        assert selected['reference_keys']==[keys[n] for n in selected['source_question_numbers']]
    else:
        key_span=next(s for s in selected['spans'] if s['role']=='published_key')
        key_text=raw[key_span['start']:key_span['end']]
        if source['kind']=='listening_table_completion':
            keys=dict((int(n),v) for n,v in re.findall(r'(1[6-9]|20)\.\s*(\S+)',key_text))
            assert selected['reference_keys']==[keys[n] for n in selected['source_question_numbers']]
        else:
            chunks=re.findall(r'(?:1-5|6-10|11-15) ([ABC]{5})',key_text);keys=dict(zip(range(1,16),''.join(chunks)))
            assert selected['reference_keys']==[keys[n] for n in selected['source_question_numbers']]
        assert selected['source_question_images']==source['source_images']
    assert selected['source'] == source['source']
    assert not selected['source_original_audio_acquired'] and not source['source_full_input_verified']
    assert not source['original_school_authenticated'] and not source['source_original_key_is_gold']
    assert selected['configuration'] == source['features']
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    grade, family, counts, roles, repeats, points = validate_draft(draft)
    assert draft['source_group_id'] == source['id']
    assert grade == group['grade'] == binding['level'] == source['level']
    assert family == binding['family'] == source['kind']
    assert counts == source['features']['subgroup_responses']
    assert source['features']['roles'] == roles and source['features']['repeat_count'] == repeats
    assert source['features']['points_each'] == points
    generation = json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript'] == audit['manuscript'] and generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
    if generation.get('marking_only_metadata_revision'):
        old_generation=json.loads(load_ref(generation['previous_audio_manifest']).read_text())
        old_draft=json.loads(load_ref(old_generation['manuscript']).read_text())
        assert generation['tracks']==old_generation['tracks'] and generation['spoken_content_and_audio_bytes_unchanged']
        assert draft['speakers']==old_draft['speakers']
        assert [(c['turns'],c['preview_seconds'],c['answer_seconds']) for c in draft['clips']]==[(c['turns'],c['preview_seconds'],c['answer_seconds']) for c in old_draft['clips']]
        assert draft['source_repeat_count']==old_draft['source_repeat_count']
    assert len(draft['clips']) == len(generation['tracks']) == len(audit['audio_assets']) == len(group['requiredAudioAssets']) == len(counts)
    assert len(group['questions']) == binding['responses'] == source['responses'] == sum(counts)
    cursor = 1
    for clip, track, asset, shown in zip(draft['clips'], generation['tracks'], audit['audio_assets'], group['requiredAudioAssets']):
        numbers = list(range(cursor, cursor+len(clip['questions'])))
        assert track['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == numbers
        assert track['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == repeats
        assert track['sha256'] == asset['sha256'] == shown['asset']['sha256']
        load_ref(asset)
        heard = [s for s in track['segments'] if s['role'] == 'dialogue']
        assert [(s['speaker'],s['text'],s['repeat']) for s in heard] == [(t['speaker'],t['text'],r) for r in range(1,repeats+1) for t in clip['turns']]
        assert len([s for s in track['segments'] if s['role'] == 'repeat_instruction']) == repeats-1
        preview, last = track['segments'][1], track['segments'][-1]
        assert preview['role'] == last['role'] == 'silence'
        assert preview['end_frame']-preview['start_frame'] == clip['preview_seconds']*track['sample_rate']
        assert last['end_frame']-last['start_frame'] == clip['answer_seconds']*track['sample_rate']
        assert track['decoded_frames'] > 0 and track['peak_abs_sample'] > 0
        assert track['dialogue_words_once'] == sum(words(t['text']) for t in clip['turns'])
        for n, q in zip(numbers, clip['questions']):
            assert group['questions'][n-1] == dict(number=n, **q)
        for t in clip['turns']:
            assert t['text'] in group['reviewText'] and t['text'] not in group['passageHtml']
        cursor += len(numbers)
    if family=='listening_table_completion':
        assert re.findall(r'\((\d+)\) ____',draft['student_table'])==[str(n) for n in range(1,6)]
        assert draft['student_table'] in audit['student_passage']
        if grade==7:
            assert draft['table_response_counts_by_row']==source['features']['response_counts_by_row']==[1,1,2,1]
            assert [q['fillMarking']['normalization'] for q in group['questions']]==['small_count_v1','english_phrase_v1','english_phrase_v1','small_count_v1','english_phrase_v1']
        else:
            assert group['questions'][0]['fillMarking']['normalization']=='clock_hour_v1'
            assert all(q['fillMarking']['normalization']=='english_phrase_v1' for q in group['questions'][1:])
        assert all(q['fillMarking']['maxWords']==1 for q in group['questions'])
        assert audit['full_fill_variant_combinations']==__import__('math').prod(len(q['acceptedAnswers']) for q in group['questions'])
    assert audit['audio_transcript_in_teacher_only'] and audit['source_companion_gap_visible']
    return True


def compile_author(manuscript, version='0.1', audio_version='0.1'):
    manuscript = manuscript.resolve(); draft = json.loads(manuscript.read_text())
    grade, family, counts, roles, repeats, points = validate_draft(draft)
    manifest = REPO/'build/english-benchmark-authority-20261017/original-audio'/(draft['id']+'-audio-v'+audio_version+'.json')
    generation = json.loads(manifest.read_text()); assert generation['manuscript'] == ref(manuscript)
    bp = load_ref(draft['source_bindings']); binding = next(b for b in json.loads(bp.read_text())['bindings'] if b['id'] == draft['source_binding'])
    material=[]; teacher=[]; tasks=[]; assets=[]
    for i,(clip,track) in enumerate(zip(draft['clips'],generation['tracks']),1):
        audio=load_ref(track); ns=track['response_numbers']
        material += ['### 材料'+str(i),'[材料'+str(i)+'（第'+str(ns[0])+'—'+str(ns[-1])+'题；'+str(repeats)+'遍）](../../../../'+str(audio.relative_to(REPO))+')']
        tasks += [dict(number=n,**q) for n,q in zip(ns,clip['questions'])]
        assets.append({k:track[k] for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']})
        teacher += ['### 材料'+str(i)+'完整原创脚本','\n\n'.join(t['speaker']+': '+t['text'] for t in clip['turns'])]
    if draft.get('student_table'):material += [draft['student_table']]
    teacher += [draft['source_notice'],draft['timing_notice'],f'本具体源型每题{points}分；本稿{len(tasks)}回应。稿件为完整原创合成试听，语流/年龄难度未独立标定；原音轨缺口不由原创录音补齐。审阅可重播，不当正式施测次数控制。']
    body='\n\n'.join(material); block=response_markdown(tasks)
    p=manuscript.parent/(draft['id']+'-v'+version+'.md'); ap=manuscript.parent/(draft['id']+'-author-check-v'+version+'.json'); assert not p.exists() and not ap.exists()
    p.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    a=dict(version=version,id=draft['id'],grade=grade,questions=len(tasks),candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=draft['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=draft.get('table_load_text',''),manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=assets,audio_transcript_in_teacher_only=True,junior_source_bound=True,source_companion_gap_visible=True,load_measure=dict(body_English_words=words(draft.get('table_load_text','')),stem_English_words=sum(words(q['stem']) for q in tasks),options_English_words_with_repeated_bank=sum(words(v) for q in tasks for _,v in q['options']),output_response_positions=len(tasks),audio_dialogue_English_words_once=sum(t['dialogue_words_once'] for t in generation['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions'] for t in generation['tracks']),audio_seconds_with_pauses=sum(t['seconds'] for t in generation['tracks']),artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    if family=='listening_table_completion':a['full_fill_variant_combinations']=__import__('math').prod(len(q['acceptedAnswers']) for q in tasks)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade=grade,family=family,family_label=draft['family_label'],title=draft['title'],questions=len(tasks),candidate=ref(p),author_check=ref(ap),source_group_ids=[draft['source_group_id']],instruction=draft['instruction'],source_form_notice=draft['source_notice'],format_summary=str(len(counts))+'材料 / '+'+'.join(map(str,counts))+'回应 / '+('五空信息表' if family=='listening_table_completion' else '每题三选')+' / 每段'+str(repeats)+'遍 / '+draft['timing_notice'])


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists()
    rows=[compile_author(m) for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=sum(m['questions'] for m in rows)))
