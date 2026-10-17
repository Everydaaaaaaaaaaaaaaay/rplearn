"""P1 six isolated words and six picture judgements; printed two-pass rule."""
import hashlib
import json
import re
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref


def validate_draft(d):
    assert d['lowprimary_picture_listening'] and d['grade'] == 'primary1'
    assert d['source_group_id'] == 'p1.unit5.2022-23.words6'
    assert d['family'] == 'listening_picture_true_false'
    assert d['source_repeat_count'] == d['render_repeat_count'] == 2
    assert d['current_nonpaper_equivalence'] is False
    assert d['source_original_audio_missing'] and d['source_reference_key_missing']
    assert d['audio_prompt_style'] == 'number_only_no_repeat_announcement'
    assert len(d['clips']) == len(d['figures']) == len(d['visual_semantics']) == 6
    assert not d.get('worked_example')
    for clip, figure, visual in zip(d['clips'], d['figures'], d['visual_semantics']):
        assert len(clip['turns']) == len(clip['questions']) == 1
        assert clip['turns'][0]['speaker'] == 'N'
        said = clip['turns'][0]['text']
        assert re.fullmatch('[a-z]+', said)
        assert clip['preview_seconds'] == 2 and clip['answer_seconds'] == 3
        q = clip['questions'][0]
        assert q['stem'] == '听录音，看图片。'
        assert q['options'] == [['√', '相符'], ['×', '不相符']]
        assert q['answer'] in ['√', '×']
        assert re.fullmatch('[a-z]+', visual['object'])
        assert q['answer'] == ('√' if said == visual['object'] else '×')
        assert said in q['rationale'] and visual['object'] in q['rationale']
        assert all(label + '：' in q['rationale'] for label in ['√', '×'])
        svg = ET.fromstring(load_ref(figure).read_bytes())
        assert svg.attrib['viewBox'] == '0 0 224 224'
        assert not ''.join(svg.itertext()).strip(), 'No noun or answer in student picture'
    return True


def validate_source(d, b, s):
    validate_draft(d)
    assert d['source_group_id'] == b['source_group_id'] == s['id']
    assert d['grade'] == b['level'] == s['level']
    assert s['responses'] == b['responses'] == 6
    assert b['task_mode'] == 'lowprimary_picture_listening'
    assert hashlib.sha256(json.dumps(s, sort_keys=True, ensure_ascii=False).encode()).hexdigest() == b['source_record_sha256']
    assert s['source_structure_verified'] and s['source_full_printed_input_verified']
    assert not any(s[k] for k in ['source_full_input_verified', 'source_original_key_is_gold', 'source_original_key_acquired', 'source_original_audio_acquired', 'original_school_authenticated'])
    assert s['features']['source_material_kind'] == 'isolated_word'
    assert s['features']['repeat_count'] == 2 and s['features']['pictures_per_response'] == 1
    assert s['features']['options_each'] == 2
    assert s['features']['responses'] == 6 and s['source_question_numbers'] == list(range(1, 7))
    sel = json.loads(load_ref(s['selected_native']).read_text())
    r = next(r for r in sel['groups'] if r['id'] == s['id'])
    assert r['full_independent_section_visible'] and len(r['printed_script']) == 6
    assert r['repeat_count'] == 2 and r['pictures_per_response'] == 1
    assert not sel['original_audio_acquired'] and not sel['published_key_page_acquired']
    for asset in sel['public_previews'] + sel['display_images']:
        load_ref(asset)
    return True
