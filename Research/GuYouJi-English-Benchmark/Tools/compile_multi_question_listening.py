#!/usr/bin/env python3
"""Compile whole source-bound listening sections without upgrading missing source input."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def check(group, audit, binding, source):
    selected = json.loads(load_ref(source['selected_native']).read_text())
    raw = load_ref(selected['source']).read_text()
    for name in ['student_span', 'key_span']:
        span = selected[name]
        assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest() == span['sha256']
    assert selected['source'] == source['source']
    assert selected['question_numbers'] == source['source_question_numbers']
    assert [len(s) for s in selected['subgroups']] == source['features']['subgroup_responses']
    assert [n for s in selected['subgroups'] for n in s] == selected['question_numbers']
    keys = {int(n): k for n, k in re.findall(r'(\d+)[.．]\s*([ABC])', raw[selected['key_span']['start']:selected['key_span']['end']])}
    assert selected['reference_keys'] == [keys[n] for n in selected['question_numbers']]
    assert not selected['source_original_audio_acquired'] and not selected['source_script_acquired']
    assert not source['source_original_audio_acquired'] and not source['source_script_acquired'] and not source['source_full_input_verified']
    assert not source['original_school_authenticated'] and source['region_and_term_body_unknown']
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    generation = json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript'] == audit['manuscript'] and generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
    assert draft['source_group_id'] == source['id'] and draft['grade'] == group['grade'] == source['level']
    assert draft['source_questions_per_clip'] == source['features']['subgroup_responses'] == [3, 3, 4]
    assert len(draft['clips']) == len(generation['tracks']) == len(audit['audio_assets']) == len(group['requiredAudioAssets']) == source['materials'] == 3
    assert len(group['questions']) == binding['responses'] == source['responses'] == 10
    cursor = 1
    for i, (clip, track, asset, shown) in enumerate(zip(draft['clips'], generation['tracks'], audit['audio_assets'], group['requiredAudioAssets']), 1):
        numbers = list(range(cursor, cursor+len(clip['questions'])))
        assert set(t['speaker'] for t in clip['turns']) == ({'N'} if i == 3 else {'M', 'W'})
        assert clip['preview_seconds'] == clip['answer_seconds'] == 5*len(numbers)
        assert track['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == numbers
        assert track['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == source['features']['repeat_count'] == 2
        assert track['sha256'] == asset['sha256'] == shown['asset']['sha256']
        load_ref(asset)
        heard = [s for s in track['segments'] if s['role'] == 'dialogue']
        assert [(s['speaker'], s['text'], s['repeat']) for s in heard] == [(t['speaker'], t['text'], r) for r in [1, 2] for t in clip['turns']]
        assert len([s for s in track['segments'] if s['role'] == 'repeat_instruction']) == 1
        preview, last = track['segments'][1], track['segments'][-1]
        assert preview['role'] == last['role'] == 'silence'
        assert preview['end_frame']-preview['start_frame'] == last['end_frame']-last['start_frame'] == clip['answer_seconds']*track['sample_rate']
        assert track['decoded_frames'] > 0 and track['peak_abs_sample'] > 0
        assert track['dialogue_words_once'] == sum(words(t['text']) for t in clip['turns'])
        for n, q in zip(numbers, clip['questions']):
            assert group['questions'][n-1] == dict(number=n, **q)
            assert [k for k, _ in q['options']] == ['A', 'B', 'C'] and q['answer'] in 'ABC' and q['rationale']
        for t in clip['turns']:
            assert t['text'] in group['reviewText'] and t['text'] not in group['passageHtml']
        cursor += len(numbers)
    assert audit['audio_transcript_in_teacher_only'] and audit['source_companion_gap_visible'] and audit['multi_question_listening']
    return True


def compile_author(manuscript, version='0.1', audio_version='0.1'):
    manuscript = manuscript.resolve(); draft = json.loads(manuscript.read_text())
    manifest = REPO/'build/english-benchmark-authority-20261017/original-audio'/(draft['id']+'-audio-v'+audio_version+'.json')
    generation = json.loads(manifest.read_text())
    assert generation['manuscript'] == ref(manuscript) and generation['whole_final_audio_decode_passed']
    bp = load_ref(draft['source_bindings']); binding = next(b for b in json.loads(bp.read_text())['bindings'] if b['id'] == draft['source_binding'])
    material = []; teacher = []; tasks = []; assets = []
    for i, (clip, track) in enumerate(zip(draft['clips'], generation['tracks']), 1):
        audio = load_ref(track); numbers = track['response_numbers']; start, end = numbers[0], numbers[-1]
        material += ['### 材料'+str(i), '[材料'+str(i)+'（第'+str(start)+'—'+str(end)+'题；两遍）](../../../../'+str(audio.relative_to(REPO))+')']
        tasks += [dict(number=n, **q) for n, q in zip(numbers, clip['questions'])]
        assets.append({k:track[k] for k in ['path', 'sha256', 'seconds', 'response_numbers', 'repeat_count', 'mime_type']})
        teacher += ['### 材料'+str(i)+'完整原创脚本', '\n\n'.join(t['speaker']+': '+t['text'] for t in clip['turns'])]
    teacher += ['两对话一独白、3/3/4题、每题三选；每段两遍，听前/听后每题5秒。音轨在第一遍后加一秒及重播提示是本机编排，原卷未核到这两项的精确时序。源每题2分，本节20分是十题计算而非原印节总分。', '公开标题称天津滨海学校下学期，正文仅确认高二第二次质量检测；地域、学期正文未知，学校原版未认证。原题面与参考键可核，原录音和脚本未取得，来源全输入未验收，不当gold。完整原创音频与脚本不填平来源缺口；本机合成音质/语流与难度未经独立教研、学生、商用或生产验证。']
    body = '\n\n'.join(material); block = response_markdown(tasks)
    p = manuscript.parent/(draft['id']+'-v'+version+'.md'); ap = manuscript.parent/(draft['id']+'-author-check-v'+version+'.json')
    assert not p.exists() and not ap.exists()
    p.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    audit = dict(version=version, id=draft['id'], grade=draft['grade'], questions=len(tasks), candidate_sha256=ref(p)['sha256'], source_binding=binding['id'], source_bindings=ref(bp), source_group_id=draft['source_group_id'], review_response_tasks=tasks, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(), student_passage=body, body_load_text='', manuscript=ref(manuscript), audio_generation=ref(manifest), audio_assets=assets, audio_transcript_in_teacher_only=True, multi_question_listening=True, source_companion_gap_visible=True, load_measure=dict(body_English_words=0, stem_English_words=sum(words(q['stem']) for q in tasks), options_English_words_with_repeated_bank=sum(words(v) for q in tasks for _, v in q['options']), output_response_positions=len(tasks), audio_dialogue_English_words_once=sum(t['dialogue_words_once'] for t in generation['tracks']), audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions'] for t in generation['tracks']), audio_seconds_with_pauses=sum(t['seconds'] for t in generation['tracks']), artifact_URLs_excluded_from_reading_load=True), source_count_increment=0, authored_student_inputs_complete=True, source_level_equivalence_established=False, independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n')
    return dict(id=draft['id'], grade=draft['grade'], family=draft['family'], family_label=draft['family_label'], title=draft['title'], questions=len(tasks), candidate=ref(p), author_check=ref(ap), source_group_ids=[draft['source_group_id']], instruction=draft['instruction'], source_form_notice='高二公开阶段卷三材料3/3/4、三选、两遍结构已核；源音频/脚本缺，学校/地域学期仍未核证，不当gold。本稿提供完整原创配套；非独立难度或施测验证。', format_summary='2长对话+1独白 / 3+3+4共10回应 / 每题三选 / 每段2遍 / 听前听后每题5秒')


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--manuscript', type=Path, action='append', required=True); p.add_argument('--metadata-output', type=Path, required=True); p.add_argument('--version', default='0.1'); p.add_argument('--audio-version', default='0.1'); a = p.parse_args()
    assert not a.metadata_output.exists()
    rows = [compile_author(m, a.version, a.audio_version) for m in a.manuscript]
    a.metadata_output.write_text(json.dumps(rows, ensure_ascii=False, indent=2)+'\n'); print(dict(groups=len(rows), responses=sum(m['questions'] for m in rows)))
