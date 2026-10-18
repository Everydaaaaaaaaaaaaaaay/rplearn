"""Bind common primary choices to whole selected sections, including joint answers."""
import hashlib
import json
import re
import unicodedata
from grade_mode_evidence import load_ref


def filled(stem, value):
    parts = value.split('; ')
    assert len(parts) == stem.count('____')
    for part in parts:
        stem = stem.replace('____', '' if part == '/' else part, 1)
    return stem


def check(group, audit, binding, source):
    selected = json.loads(load_ref(source['selected_native']).read_text())
    block = selected['selected_native_block']
    assert hashlib.sha256(block.encode()).hexdigest() == selected['block_sha256']
    if selected.get('source_native_subsection') == 'primary5_guilin11':
        from bs4 import BeautifulSoup
        native = BeautifulSoup(load_ref(selected['source_html']).read_text(), 'html.parser').get_text('\n', strip=True)
        assert source['level'] == 'primary5' and '小学五年级' in native
        assert native[selected['start_offset']:selected['end_offset']] == block
        assert [r['ordinal'] for r in selected['items']] == list(range(1, 11))
        assert [r['printed_number'] for r in selected['items']] == [52, 53, 54, None, None, None, 58, None, None, 61]
        assert [r['visible_blank_slots'] for r in selected['items']] == source['features']['visible_blank_slots_each']
        assert len(re.findall(r'(?<![A-Za-z])[ABC]\.', unicodedata.normalize('NFKC', block))) == 30
        assert selected['published_key_raw'] in native
        assert selected['published_key_vector'] == list('CBCBBBACAB')
        assert selected['source_original_key_acquired'] and source['source_key_acquired']
        assert source['source_key_is_gold'] is False
    else:
        numbers = re.findall(r'(?m)^(?:[（(]\s*[）)]\s*)?(\d+)\.', block)
        assert list(map(int, numbers)) == list(range(1, 11))
        assert len(re.findall(r'(?<![A-Za-z])[ABC]\.', block)) == 30
        assert not selected['source_original_key_acquired']
        assert not source['source_key_acquired']
    assert not selected['source_school_authenticated']
    assert not source['school_exam_authentication']
    assert source['input_layer'] == 'selected_native_text_only'
    assert binding['source_features'] == source['features'] == audit['source_features']
    assert binding['level'] == group['grade'] == source['level']
    expected = source['features']['visible_blank_slots_each']
    assert len(group['questions']) == 10 == source['responses']
    assert [q['stem'].count('____') for q in group['questions']] == expected
    assert source['features']['joint_choice_positions'] == [n for n, count in enumerate(expected, 1) if count > 1]
    assert not group['requiredPassageImages'] and not group.get('requiredAudioAssets')
    for q, reasons, backfills in zip(group['questions'], audit['candidate_reason_rows'], audit['all_candidate_backfills']):
        assert [p[0] for p in q['options']] == list('ABC')
        assert len({t.casefold() for _, t in q['options']}) == 3
        assert q['answer'] == reasons['key'] and all(reasons['grounds'][k] for k in 'ABC')
        assert backfills == {k: filled(q['stem'], text) for k, text in q['options']}
        assert q['rationale'] == '；'.join(k+'：'+reasons['grounds'][k] for k in 'ABC')
    assert len(audit['candidate_reason_rows']) == len(audit['all_candidate_backfills']) == 10
    if source['level'] == 'primary4':
        fourth = group['questions'][3]
        assert dict(fourth['options'])[fourth['answer']].split('; ')[-1] == '/'
        assert 'every ' in fourth['stem']
        assert all(len(re.findall('[\u4e00-\u9fff]', t)) > 0 for _, t in group['questions'][9]['options'])
    return True
