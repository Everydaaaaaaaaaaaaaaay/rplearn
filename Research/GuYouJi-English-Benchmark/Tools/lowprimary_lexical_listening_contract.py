"""Whole legacy P2 auditory-identification modes, separate from current nonpaper tasks."""
import hashlib
import json
import re
from grade_mode_evidence import load_ref


MODES = {
    'p2.szxuexiao1926.undated-final.words10': ('listening_word_phrase_choice', 10, 'ABC'),
    'p2.szxuexiao1926.undated-final.sentences8': ('listening_sentence_choice', 8, 'AB'),
}


def normalized(text):
    return re.sub(r'[.!?]+$', '', text.strip()).casefold()


def validate_draft(d):
    family, count, labels = MODES[d['source_group_id']]
    assert d['lowprimary_lexical_listening'] and d['grade'] == 'primary2'
    assert d['family'] == family and len(d['clips']) == count
    assert d['source_repeat_count'] == d['render_repeat_count'] == 2
    assert d['source_hear_each_piece_twice'] and d['source_original_audio_missing']
    assert d['current_nonpaper_equivalence'] is False
    assert not d.get('worked_example')
    for c in d['clips']:
        assert len(c['turns']) == len(c['questions']) == 1
        assert c['turns'][0]['speaker'] == 'N'
        assert c['preview_seconds'] == 2 and c['answer_seconds'] == 3
        q = c['questions'][0]
        assert [k for k, _ in q['options']] == list(labels)
        assert q['answer'] in list(labels)
        assert all(isinstance(v, str) and v.strip() for _, v in q['options'])
        assert len({normalized(v) for _, v in q['options']}) == len(labels)
        said = c['turns'][0]['text']
        assert [k for k, v in q['options'] if normalized(v) == normalized(said)] == [q['answer']]
        if family == 'listening_word_phrase_choice':
            assert 1 <= len(re.findall(r'[A-Za-z]+', said)) <= 3
            assert not re.search(r'[.!?]', said)
            assert all(1 <= len(re.findall(r'[A-Za-z]+', v)) <= 3 and not re.search(r'[.!?]', v) for _, v in q['options'])
        else:
            assert said[-1] in '.?' and len(re.findall(r'[A-Za-z]+', said)) >= 3
            assert all(v[-1] in '.?' and len(re.findall(r'[A-Za-z]+', v)) >= 3 for _, v in q['options'])
        reasons = dict(s.split('：', 1) for s in q['rationale'].split('；'))
        assert set(reasons) == set(labels) and all(reasons.values())
    return True


def validate_source(d, binding, source):
    validate_draft(d)
    family, count, labels = MODES[d['source_group_id']]
    assert d['source_group_id'] == source['id'] == binding['source_group_id']
    assert source['level'] == binding['level'] == d['grade']
    assert source['kind'] == binding['family'] == family
    assert source['responses'] == binding['responses'] == count
    assert hashlib.sha256(json.dumps(source, sort_keys=True, ensure_ascii=False).encode()).hexdigest() == binding['source_record_sha256']
    assert source['source_full_printed_input_verified'] and source['source_structure_verified']
    assert not source['source_full_input_verified'] and not source['source_original_audio_acquired']
    assert not source['source_original_key_is_gold'] and not source['original_school_authenticated']
    assert source['features']['options_each'] == len(labels)
    assert source['features']['repeat_count'] == 2 and source['features']['solved_examples'] == 0
    assert source['year'] is None and source['semester'] is None and source['body_region'] is None
    selected = json.loads(load_ref(source['selected_native']).read_text())
    row = next(r for r in selected['groups'] if r['id'] == source['id'])
    assert len(row['options']) == len(row['printed_script']) == len(row['published_key']) == count
    assert row['repeat_count'] == 2 and all(len(v) == len(labels) for v in row['options'])
    # Preserve two printed A. markers as source artifacts; they do not prove spoken audio.
    for opts, key, script in zip(row['options'], row['published_key'], row['printed_script']):
        if script.startswith('A.'):
            script = script[2:]
        assert normalized(opts[labels.index(key)]) == normalized(script)
    assert selected['full_source_audio_acquired'] is False
    load_ref(selected['source_reader'])
    return True
