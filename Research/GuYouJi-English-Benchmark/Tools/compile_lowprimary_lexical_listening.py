"""Compile complete P2 word/phrase and sentence identification, never source audio."""
import hashlib
import json
from grade_mode_evidence import REPO, load_ref
from compile_short_dialogue_listening import ref
from quality_review_contract import response_markdown
from render_original_listening import words
from lowprimary_lexical_listening_contract import validate_source


def bound(d):
    bp = load_ref(d['source_bindings'])
    b = next(r for r in json.loads(bp.read_text())['bindings'] if r['id'] == d['source_binding'])
    s = next(r for r in json.loads(load_ref(b['source_index']).read_text())[b['collection']] if r['id'] == b['source_group_id'])
    validate_source(d, b, s)
    return bp, b, s


def compile_author(manuscript, version="0.1"):
    d = json.loads(manuscript.read_text()); bp, b, s = bound(d)
    mp = REPO / 'build/english-benchmark-authority-20261017/original-audio' / (d['id'] + '-audio-v0.1.json')
    gen = json.loads(mp.read_text())
    assert gen['manuscript'] == ref(manuscript) and gen['whole_final_audio_decode_passed']
    assert len(gen['tracks']) == len(d['clips'])
    body = []; teacher = []; qs = []; assets = []; pairs = []
    for n, (clip, track) in enumerate(zip(d['clips'], gen['tracks']), 1):
        audio = load_ref(track)
        body += ['[录音' + str(n) + '（两遍）](../../../../' + str(audio.relative_to(REPO)) + ')']
        q = dict(number=n, **clip['questions'][0]); qs.append(q)
        assets.append({k: track[k] for k in ['path', 'sha256', 'seconds', 'response_numbers', 'repeat_count', 'mime_type']})
        teacher.append('第' + str(n) + '项完整原创脚本：' + clip['turns'][0]['text'])
        reasons = dict(v.split('：', 1) for v in q['rationale'].split('；'))
        pairs += [dict(number=n, candidate=k, text=v, is_reference=k == q['answer'], reason=reasons[k]) for k, v in q['options']]
    teacher.append(d['source_notice'])
    passage = '\n\n'.join(body); block = response_markdown(qs)
    candidate = manuscript.with_name(d['id'] + '-v' + version + '.md'); ap = manuscript.with_name(d['id'] + '-author-check-v' + version + '.json')
    assert not candidate.exists() and not ap.exists()
    candidate.write_text('# ' + d['title'] + '\n\n## 学生题面\n\n' + d['instruction'] + '\n\n' + passage + '\n\n<!-- responses:start -->\n\n' + block + '\n\n<!-- responses:end -->\n\n## 作者核对\n\n' + '\n\n'.join(teacher) + '\n')
    a = dict(version=version, id=d['id'], grade='primary2', questions=len(qs), candidate_sha256=ref(candidate)['sha256'], source_binding=b['id'], source_bindings=ref(bp), source_group_id=s['id'], manuscript=ref(manuscript), audio_generation=ref(mp), audio_assets=assets, audio_transcript_in_teacher_only=True, lowprimary_lexical_listening=True, review_response_tasks=qs, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(), student_passage=passage, body_load_text='', candidate_pair_audit=pairs, source_count_increment=0, authored_student_inputs_complete=True, source_level_equivalence_established=False, independent_teacher_student_commercial_production_validated=False, load_measure=dict(body_English_words=0, stem_English_words=sum(words(q['stem']) for q in qs), options_English_words_with_repeated_bank=sum(words(v) for q in qs for _,v in q['options']), output_instruction_English_words=words(d['instruction']), output_response_positions=len(qs), audio_dialogue_English_words_once=sum(t['dialogue_words_once'] for t in gen['tracks']), audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions'] for t in gen['tracks']), audio_seconds_with_pauses=sum(t['seconds'] for t in gen['tracks']), artifact_URLs_excluded_from_reading_load=True))
    ap.write_text(json.dumps(a, ensure_ascii=False, indent=2) + '\n')
    return dict(id=d['id'], grade='primary2', family=d['family'], family_label=d['family_label'], title=d['title'], questions=len(qs), candidate=ref(candidate), author_check=ref(ap), source_group_ids=[s['id']], instruction=d['instruction'], source_form_notice=d['source_notice'], format_summary=d['format_summary'])


def check(g, a, b, s):
    d = json.loads(load_ref(a['manuscript']).read_text()); validate_source(d, b, s)
    gen = json.loads(load_ref(a['audio_generation']).read_text())
    assert gen['manuscript'] == a['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    count = s['responses']
    assert g['grade'] == 'primary2' and len(g['questions']) == len(g['requiredAudioAssets']) == len(a['audio_assets']) == len(gen['tracks']) == count
    for n, (clip, track, asset, shown, question) in enumerate(zip(d['clips'], gen['tracks'], a['audio_assets'], g['requiredAudioAssets'], g['questions']), 1):
        assert question == dict(number=n, **clip['questions'][0])
        assert track['response_numbers'] == asset['response_numbers'] == shown['response_numbers'] == [n]
        assert track['repeat_count'] == asset['repeat_count'] == shown['repeat_count'] == 2
        assert track['sha256'] == asset['sha256'] == shown['asset']['sha256']; load_ref(asset)
        heard = [v for v in track['segments'] if v['role'] == 'dialogue']
        assert [(v['text'],v['repeat']) for v in heard] == [(clip['turns'][0]['text'], 1), (clip['turns'][0]['text'], 2)]
        assert track['decoded_frames'] > 0 and track['peak_abs_sample'] > 0
        assert clip['turns'][0]['text'] in g['reviewText']
        assert clip['turns'][0]['text'] not in g['passageHtml']
        assert track['dialogue_words_once'] == words(clip['turns'][0]['text'])
        reasons = dict(v.split('：',1) for v in question['rationale'].split('；'))
        for k,v in question['options']:
            p = next(p for p in a['candidate_pair_audit'] if p['number']==n and p['candidate']==k)
            assert p == dict(number=n,candidate=k,text=v,is_reference=k==question['answer'],reason=reasons[k])
    assert len(a['candidate_pair_audit']) == count * s['features']['options_each']
    return True
