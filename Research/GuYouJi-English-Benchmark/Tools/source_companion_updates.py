"""Expose subsequent source evidence without rewriting frozen authored payloads."""
import json
import hashlib
import re
from datetime import date
from grade_mode_evidence import load_ref


def _native_questions(text):
    rows = []
    current = None
    for line in text.splitlines():
        line = line.strip()
        match = re.match(r'^(\d{1,2})\.\s*(.*)$', line)
        if match and 1 <= int(match[1]) <= 20:
            current = dict(number=int(match[1]), stem=match[2], option_lines=[])
            rows.append(current)
        elif current and re.match(r'^[ABC]\.', line):
            current['option_lines'].append(line)
        elif current and not current['option_lines'] and line and not re.match(r'^(听|第一|第二|高三英语)', line):
            current['stem'] += ' ' + line
    for row in rows:
        options = ' '.join(row.pop('option_lines'))
        row['options'] = [[m[1], m[2].strip()] for m in re.finditer(r'(?:^|\s)([ABC])\.\s*(.*?)(?=\s[ABC]\.|$)', options)]
        assert [o[0] for o in row['options']] == list('ABC')
    return rows


def _validate_related_family(review, source):
    """A sibling publication can inform a source, without becoming its original."""
    from bs4 import BeautifulSoup
    family = json.loads(load_ref(review['family_alignment']).read_text())
    selected = json.loads(load_ref(family['selected_native']).read_text())
    native = BeautifulSoup(load_ref(selected['source_html']).read_text(), 'html.parser').get_text('\n', strip=True)
    original = load_ref(selected['yinchuan_source']).read_text()
    assert source['source'] == selected['yinchuan_source'] and source['level'] == 11
    assert review['source_group_id'] in family['existing_source_group_ids']
    assert family['same_material_family_not_independent_exposure'] is True
    assert family['does_not_prove_grade11_grade12_equivalence'] is True
    assert family['related_publication_question14_to20_not_native_visible'] is True
    for key in ['original_yinchuan_recording_acquired', 'original_yinchuan_printed_transcript_acquired',
                'original_yinchuan_published_listening_key_acquired', 'source_key_independent_gold']:
        assert family[key] is False
    scripts = native[selected['script_start']:selected['script_end']]
    questions = native[selected['question_block_start']:selected['question_block_end']]
    assert hashlib.sha256(scripts.encode()).hexdigest() == selected['script_block_sha256']
    assert hashlib.sha256(questions.encode()).hexdigest() == selected['question_block_sha256']
    assert '高三英语' in questions and '每段录音播放两遍' in questions
    source_questions = original[selected['yinchuan_listening_start']:selected['yinchuan_listening_end']]
    assert _native_questions(source_questions) == selected['yinchuan_question_rows']
    assert [q['number'] for q in selected['yinchuan_question_rows']] == list(range(1, 21))
    visible = _native_questions(questions)
    assert [q['number'] for q in visible] == list(range(1, 14))
    normalize = lambda value: ' '.join(re.findall('[a-z0-9]+', value.lower()))
    pairs = selected['visible_first13_comparison']
    assert len(pairs) == 13
    for original_row, other_row, pair in zip(selected['yinchuan_question_rows'], visible, pairs):
        assert pair['yinchuan'] == original_row and pair['fuzhou'] == other_row
        assert pair['stem_tokens_equal'] is True and normalize(original_row['stem']) == normalize(other_row['stem'])
        assert pair['option_tokens_equal'] == [normalize(a[1]) == normalize(b[1]) for a, b in zip(original_row['options'], other_row['options'])]
    assert [p['number'] for p in pairs if not all(p['option_tokens_equal'])] == [1, 2, 5, 7, 9, 11]
    assert [r['number'] for r in selected['scripts']] == list(range(1, 11))
    for record in selected['scripts']:
        raw = native[record['start_offset']:record['end_offset']]
        assert raw == record['raw'] and hashlib.sha256(raw.encode()).hexdigest() == record['sha256']
        assert raw.startswith('Text ' + str(record['number']) + '\n')
    assert native[selected['published_key_start']:selected['published_key_end']] == selected['published_key_raw']
    key = re.fullmatch(r'1—5\s+([ABC]{5})\s+6—10\s+([ABC]{5})\s+11—15\s+([ABC]{5})\s+16—20\s+([ABC]{5})', selected['published_key_raw'])
    assert key and ''.join(key.groups()) == ''.join(selected['published_key_vector'])
    assert ''.join(selected['published_key_vector']) == 'CCABACABBCBBCABACBAC'
    assert family['published_other_parent_key_vector'] == selected['published_key_vector']
    assert family['conditional_candidate_vector'] == selected['published_key_vector']
    assert [r['number'] for r in family['candidate_rationales']] == list(range(1, 21))
    mapping = [1, 2, 3, 4, 5, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10]
    for row, material, question in zip(family['candidate_rationales'], mapping, selected['yinchuan_question_rows']):
        record = selected['scripts'][material - 1]
        assert row['material'] == material and record['start_offset'] <= row['cue_start'] < row['cue_end'] <= record['end_offset']
        assert native[row['cue_start']:row['cue_end']] == row['cue']
        assert [[r['letter'], r['text']] for r in row['candidate_reasons']] == question['options']
        assert all(r['reason'].strip() for r in row['candidate_reasons'])
        assert row['conditional_candidate_letter'] == family['conditional_candidate_vector'][row['number'] - 1]
        assert row['fuzhou_same_question_visible'] == (row['number'] <= 13)
    assert review['original_source_question_numbers'] == source['source_question_numbers']
    assert review['conditional_alignment_only'] is True
    assert review['whole_first_section_printed_inputs_verified'] is False
    assert review['original_source_script_acquired'] is False and review['source_original_key_acquired'] is False
    assert review['related_source_published_script_and_key_acquired'] is True


def validate_update(update, review, groups):
    assert update['does_not_change_authored_input_or_answer'] is True and update['does_not_admit_source_audio_or_gold'] is True
    date.fromisoformat(update['checked_on'])
    assert isinstance(update['notice'], str) and update['notice'].strip()
    assert isinstance(update['label'], str) and update['label'].strip()
    assert review['scope'] in ['whole_independent_source_section_companion_followup', 'cross_parent_material_family_companion_followup']
    assert update['source_group_ids'] == [review['source_group_id']]
    targets = sorted(g['id'] for g in groups.values() if review['source_group_id'] in g['anchor_group_ids'])
    assert targets and sorted(update['author_group_ids']) == targets
    assert len(set(update['author_group_ids'])) == len(targets)
    assert review['source_written_input_layer_strengthened'] is True
    if review['scope'] == 'whole_independent_source_section_companion_followup':
        assert review['whole_first_section_printed_inputs_verified'] is True
    assert all(review[k] is False for k in ['source_original_audio_acquired', 'whole_source_full_input_verified', 'source_key_independent_gold', 'original_school_release_authenticated', 'all_required_types_complete'])
    assert all(type(review[k]) is int and review[k] == 0 for k in ['new_authenticated_parent_papers', 'new_authored_groups', 'new_response_positions'])
    for ident in targets:
        audit = json.loads(load_ref(groups[ident]['author_check']).read_text())
        bindings = json.loads(load_ref(audit['source_bindings']).read_text())
        binding = next(b for b in bindings['bindings'] if b['id'] == audit['source_binding'])
        source = next(s for s in json.loads(load_ref(binding['source_index']).read_text())[binding['collection']] if s['id'] == binding['source_group_id'])
        assert source['id'] == review['source_group_id']
        assert source['features'] == review['configuration']
        assert len(groups[ident]['questions']) == review['configuration']['responses']
        if review['scope'] == 'cross_parent_material_family_companion_followup':
            _validate_related_family(review, source)
    return True


def load_updates(plan, groups):
    reference = plan.get('current_source_companion_updates')
    if not reference:
        return []
    index = json.loads(load_ref(reference).read_text())
    assert index['scope'] == 'source_companion_notes_separate_from_frozen_authored_groups'
    updates = index['updates']
    assert len({u['id'] for u in updates}) == len(updates)
    for update in updates:
        review = json.loads(load_ref(update['review']).read_text())
        validate_update(update, review, groups)
        for asset in review['evidence']:
            load_ref(asset)
    return updates
