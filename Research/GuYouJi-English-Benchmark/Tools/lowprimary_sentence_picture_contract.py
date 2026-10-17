"""Whole P1 ten-sentence/two-picture form, distinct from the six-word judgements."""
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref


def validate_draft(d):
    assert d['lowprimary_sentence_picture'] and d['grade'] == 'primary1'
    assert d['source_group_id'] == 'p1.unit5.2022-23.sentences10'
    assert d['family'] == 'listening_picture_choice'
    assert d['source_repeat_count'] == d['render_repeat_count'] == 2
    assert d['current_nonpaper_equivalence'] is False
    assert d['source_original_audio_missing'] and d['source_reference_key_missing']
    assert d['audio_prompt_style'] == 'number_only_no_repeat_announcement'
    assert len(d['clips']) == len(d['semantic_pairs']) == 10
    assert not d.get('worked_example')
    for c, pair in zip(d['clips'], d['semantic_pairs']):
        assert len(c['turns']) == len(c['questions']) == 1
        assert c['turns'][0]['speaker'] == 'N'
        said = c['turns'][0]['text']
        assert said[-1] in '.!?' and len(re.findall('[A-Za-z]+', said)) >= 3
        assert c['preview_seconds'] == 2 and c['answer_seconds'] == 3
        q = c['questions'][0]
        assert q['stem'] == '听句子，选图片。'
        assert q['options'] == [['A', '图A'], ['B', '图B']]
        assert q['answer'] in ['A', 'B']
        assert list(q['optionImageAssets']) == ['A', 'B']
        assert len({r['sha256'] for r in q['optionImageAssets'].values()}) == 2
        assert pair['sentence'] == said and pair['reference'] == q['answer']
        assert pair['A'] != pair['B'] and pair['best_picture'] == pair[q['answer']]
        assert all(k + '：' in q['rationale'] for k in ['A', 'B'])
        for figure in q['optionImageAssets'].values():
            svg = ET.fromstring(load_ref(figure).read_bytes())
            assert svg.attrib['viewBox'] == '0 0 224 224'
            assert not ''.join(svg.itertext()).strip()
    return True


def validate_source(d, b, s):
    validate_draft(d)
    assert s['id'] == b['source_group_id'] == d['source_group_id']
    assert s['level'] == b['level'] == d['grade']
    assert s['responses'] == b['responses'] == 10
    assert b['task_mode'] == 'lowprimary_picture_listening'
    assert hashlib.sha256(json.dumps(s, sort_keys=True, ensure_ascii=False).encode()).hexdigest() == b['source_record_sha256']
    assert s['source_structure_verified'] and s['source_full_printed_input_verified']
    assert s['features']['responses'] == 10 and s['features']['repeat_count'] == 2
    assert s['features']['source_material_kind'] == 'sentence'
    assert s['features']['options_each'] == s['features']['pictures_per_response'] == 2
    assert not any(s[k] for k in ['source_full_input_verified', 'source_original_audio_acquired', 'source_original_key_is_gold', 'source_original_key_acquired', 'original_school_authenticated'])
    sel = json.loads(load_ref(s['selected_native']).read_text())
    r = next(r for r in sel['groups'] if r['id'] == s['id'])
    assert len(r['printed_script']) == 10 and r['full_independent_section_visible']
    assert r['pictures_per_response'] == r['repeat_count'] == 2
    assert not sel['original_audio_acquired'] and not sel['published_key_page_acquired']
    for figure in sel['public_previews']:
        load_ref(figure)
    return True
