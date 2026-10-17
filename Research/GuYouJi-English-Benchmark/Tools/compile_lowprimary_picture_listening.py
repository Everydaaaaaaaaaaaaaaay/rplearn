"""Compile P1 words, preserving full six-response form and owned visual/audio inputs."""
import hashlib
import json
from grade_mode_evidence import REPO, load_ref
from compile_short_dialogue_listening import ref
from quality_review_contract import response_markdown
from render_original_listening import words
from lowprimary_picture_listening_contract import validate_source


def bound(d):
    bp = load_ref(d['source_bindings'])
    b = next(b for b in json.loads(bp.read_text())['bindings'] if b['id'] == d['source_binding'])
    s = next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']] if s['id'] == b['source_group_id'])
    validate_source(d, b, s)
    return bp, b, s


def compile_author(manuscript):
    d = json.loads(manuscript.read_text()); bp, b, s = bound(d)
    mp = REPO / 'build/english-benchmark-authority-20261017/original-audio' / (d['id'] + '-audio-v' + d['audio_version'] + '.json')
    gen = json.loads(mp.read_text())
    assert gen['manuscript'] == ref(manuscript) and gen['whole_final_audio_decode_passed']
    assert len(gen['tracks']) == 6
    body = []; teacher = []; qs = []; assets = []
    for n, (clip, track, fig) in enumerate(zip(d['clips'], gen['tracks'], d['figures']), 1):
        audio = load_ref(track); fp = load_ref(fig)
        body += ['![第' + str(n) + '图](../../../../' + str(fp.relative_to(REPO)) + ')', '[录音' + str(n) + '（两遍）](../../../../' + str(audio.relative_to(REPO)) + ')']
        qs.append(dict(number=n, **clip['questions'][0]))
        assets.append({k: track[k] for k in ['path', 'sha256', 'seconds', 'response_numbers', 'repeat_count', 'mime_type']})
        teacher.append('第' + str(n) + '项原创孤立词：' + clip['turns'][0]['text'] + '；自有图义：' + d['visual_semantics'][n-1]['object'])
    teacher.append(d['source_notice'])
    passage = '\n\n'.join(body); block = response_markdown(qs)
    p = manuscript.with_name(d['id'] + '-v0.1.md'); ap = manuscript.with_name(d['id'] + '-author-check-v0.1.json')
    assert not p.exists() and not ap.exists()
    p.write_text('# ' + d['title'] + '\n\n## 学生题面\n\n' + d['instruction'] + '\n\n' + passage + '\n\n<!-- responses:start -->\n\n' + block + '\n\n<!-- responses:end -->\n\n## 作者核对\n\n' + '\n\n'.join(teacher) + '\n')
    a = dict(version='0.1', id=d['id'], grade=d['grade'], questions=6, candidate_sha256=ref(p)['sha256'], source_binding=b['id'], source_bindings=ref(bp), source_group_id=s['id'], manuscript=ref(manuscript), audio_generation=ref(mp), audio_assets=assets, figure_assets=d['figures'], audio_transcript_in_teacher_only=True, lowprimary_picture_listening=True, picture_listening=True, review_response_tasks=qs, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(), student_passage=passage, body_load_text='', source_count_increment=0, authored_student_inputs_complete=True, source_level_equivalence_established=False, independent_teacher_student_commercial_production_validated=False, load_measure=dict(body_English_words=0, stem_English_words=0, options_English_words_with_repeated_bank=0, output_instruction_English_words=words(d['instruction']), output_response_positions=6, visual_panels=6, audio_dialogue_English_words_once=6, audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions'] for t in gen['tracks']), audio_seconds_with_pauses=sum(t['seconds'] for t in gen['tracks']), artifact_URLs_excluded_from_reading_load=True))
    ap.write_text(json.dumps(a, ensure_ascii=False, indent=2) + '\n')
    return dict(id=d['id'], grade=d['grade'], family=d['family'], family_label=d['family_label'], title=d['title'], questions=6, candidate=ref(p), author_check=ref(ap), source_group_ids=[s['id']], instruction=d['instruction'], source_form_notice=d['source_notice'], format_summary=d['format_summary'])


def check(g, a, b, s):
    d = json.loads(load_ref(a['manuscript']).read_text()); validate_source(d, b, s)
    gen = json.loads(load_ref(a['audio_generation']).read_text())
    assert gen['manuscript'] == a['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    assert len(g['questions']) == len(g['requiredAudioAssets']) == len(g['requiredPassageImages']) == len(gen['tracks']) == len(a['audio_assets']) == 6
    assert g['grade'] == 'primary1' and a['audio_transcript_in_teacher_only']
    for n, (clip, track, asset, shown, img, fig, q) in enumerate(zip(d['clips'], gen['tracks'], a['audio_assets'], g['requiredAudioAssets'], g['requiredPassageImages'], d['figures'], g['questions']), 1):
        assert q == dict(number=n, **clip['questions'][0])
        assert track['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == [n]
        assert track['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == 2
        assert track['sha256'] == asset['sha256'] == shown['asset']['sha256']; load_ref(asset)
        assert img['asset'] == fig and img['alt'] == '第' + str(n) + '图'
        assert [(v['text'], v['repeat']) for v in track['segments'] if v['role'] == 'dialogue'] == [(clip['turns'][0]['text'], 1), (clip['turns'][0]['text'], 2)]
        assert not any(v['role'] == 'repeat_instruction' for v in track['segments'])
        assert track['segments'][0]['text'] == str(n) + '.'
        assert track['decoded_frames'] > 0 and track['peak_abs_sample'] > 0
        assert clip['turns'][0]['text'] in g['reviewText']
        assert '<audio' in g['passageHtml'] and '<img' in g['passageHtml']
        assert not any(clip['turns'][0]['text'] in text for text in [q['stem']] + [v for _, v in q['options']])
    assert a['load_measure']['audio_dialogue_English_words_once'] == 6
    return True
