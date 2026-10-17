"""Compile complete ten-sentence picture-choice groups with owned media."""
import hashlib
import json
from grade_mode_evidence import REPO, load_ref
from compile_short_dialogue_listening import ref
from quality_review_contract import response_markdown
from quality_review_images import check_option_images, without_derived_images
from render_original_listening import words
from lowprimary_sentence_picture_contract import validate_source


def bound(d):
    bp = load_ref(d['source_bindings'])
    b = next(b for b in json.loads(bp.read_text())['bindings'] if b['id'] == d['source_binding'])
    s = next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']] if s['id'] == b['source_group_id'])
    validate_source(d, b, s)
    return bp, b, s


def compile_author(manuscript):
    d = json.loads(manuscript.read_text()); bp, b, s = bound(d)
    mp = REPO / 'build/english-benchmark-authority-20261017/original-audio' / (d['id'] + '-audio-v0.1.json')
    gen = json.loads(mp.read_text()); assert gen['manuscript'] == ref(manuscript) and gen['whole_final_audio_decode_passed']
    body = []; teacher = []; qs = []; assets = []
    for n, (c, t) in enumerate(zip(d['clips'], gen['tracks']), 1):
        body.append('[录音' + str(n) + '（两遍）](../../../../' + str(load_ref(t).relative_to(REPO)) + ')')
        qs.append(dict(number=n, **c['questions'][0])); assets.append({k: t[k] for k in ['path', 'sha256', 'seconds', 'response_numbers', 'repeat_count', 'mime_type']})
        teacher.append('第' + str(n) + '项完整原创句子：' + c['turns'][0]['text'] + '；图义对照：' + json.dumps(d['semantic_pairs'][n-1], ensure_ascii=False))
    teacher.append(d['source_notice']); passage = '\n\n'.join(body); block = response_markdown(qs)
    p = manuscript.with_name(d['id'] + '-v0.1.md'); ap = manuscript.with_name(d['id'] + '-author-check-v0.1.json'); assert not p.exists() and not ap.exists()
    p.write_text('# ' + d['title'] + '\n\n## 学生题面\n\n' + d['instruction'] + '\n\n' + passage + '\n\n<!-- responses:start -->\n\n' + block + '\n\n<!-- responses:end -->\n\n## 作者核对\n\n' + '\n\n'.join(teacher) + '\n')
    a = dict(version='0.1', id=d['id'], grade=d['grade'], questions=10, candidate_sha256=ref(p)['sha256'], source_binding=b['id'], source_bindings=ref(bp), source_group_id=s['id'], manuscript=ref(manuscript), audio_generation=ref(mp), audio_assets=assets, audio_transcript_in_teacher_only=True, lowprimary_sentence_picture=True, illustrated_listening=True, review_response_tasks=qs, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(), student_passage=passage, body_load_text='', source_count_increment=0, authored_student_inputs_complete=True, source_level_equivalence_established=False, independent_teacher_student_commercial_production_validated=False, load_measure=dict(body_English_words=0, stem_English_words=0, options_English_words_with_repeated_bank=sum(words(v) for q in qs for _, v in q['options']), option_image_English_words=0, option_image_number_tokens=0, output_response_positions=10, picture_option_positions=20, audio_dialogue_English_words_once=sum(t['dialogue_words_once'] for t in gen['tracks']), audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions'] for t in gen['tracks']), audio_seconds_with_pauses=sum(t['seconds'] for t in gen['tracks'])))
    ap.write_text(json.dumps(a, ensure_ascii=False, indent=2) + '\n')
    return dict(id=d['id'], grade=d['grade'], family=d['family'], family_label=d['family_label'], title=d['title'], questions=10, candidate=ref(p), author_check=ref(ap), source_group_ids=[s['id']], instruction=d['instruction'], source_form_notice=d['source_notice'], format_summary=d['format_summary'])


def check(g, a, b, s):
    d = json.loads(load_ref(a['manuscript']).read_text()); validate_source(d, b, s)
    gen = json.loads(load_ref(a['audio_generation']).read_text())
    assert gen['manuscript'] == a['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    assert len(g['questions']) == len(g['requiredAudioAssets']) == len(a['audio_assets']) == len(gen['tracks']) == 10
    assert not g['requiredPassageImages'] and check_option_images(g) == 20
    assert without_derived_images(g['questions']) == a['review_response_tasks']
    assert a['review_response_tasks'] == [dict(number=n, **c['questions'][0]) for n, c in enumerate(d['clips'], 1)]
    assert g['grade'] == 'primary1' and a['audio_transcript_in_teacher_only']
    for n, (c, t, asset, shown) in enumerate(zip(d['clips'], gen['tracks'], a['audio_assets'], g['requiredAudioAssets']), 1):
        assert t['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == [n]
        assert t['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == 2
        assert t['sha256'] == asset['sha256'] == shown['asset']['sha256']; load_ref(asset)
        assert [(v['text'], v['repeat']) for v in t['segments'] if v['role'] == 'dialogue'] == [(c['turns'][0]['text'], 1), (c['turns'][0]['text'], 2)]
        assert not any(v['role'] == 'repeat_instruction' for v in t['segments'])
        assert t['segments'][0]['text'] == str(n) + '.' and t['decoded_frames'] > 0 and t['peak_abs_sample'] > 0
        assert c['turns'][0]['text'] in g['reviewText'] and c['turns'][0]['text'] not in g['passageHtml']
    return True
