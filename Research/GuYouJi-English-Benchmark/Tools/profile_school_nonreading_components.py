#!/usr/bin/env python3
"""Measure explicit source views of fill-in, translation, open answers and writing.

Input and output burden differ; English token counts miss Chinese instructions,
visual layout and cognitive load. No grade threshold or student-time inference.
"""
import hashlib
import json
import re
from grade_mode_evidence import BASE, REPO, CURRENT_BATCHES, load_ref
from profile_task_load import count

# Boundaries describe the saved native text, not a repaired student document.
CASES = [
    ('grade9-zhongshan2025-21cnjy22278047', 'bank', 'A cook at a university', '\n五、读写综合(', list(range(41, 51)), 'bare', 'gapped_material', 10),
    ('grade9-zhongshan2025-21cnjy22278047', 'bank', 'leave     read', '\nA cook at a university', [], None, 'shared_word_bank', 12),
    ('grade9-zhongshan2025-21cnjy22278047', 'open', 'Jade, a 30-year-old', '\n51. How long', [], None, 'reading_material_for_open_answers', 1),
    ('grade9-zhongshan2025-21cnjy22278047', 'open', '51. How long', '\nB.书面表达', list(range(51, 56)), 'line_labels', 'five_question_stems', 5),
    ('grade10-jinhua2025-21cnjy22399612', 'grammar', 'Between 15,000', '\n第四部分 写作', list(range(56, 66)), 'underscored', 'gapped_material_with_given_words', 10),
    ('grade10-jinhua2025-21cnjy22399612', 'translation', '66. 这家博物馆', '\n第二节 应用文写作', list(range(66, 71)), 'line_labels', 'Chinese_prompts_and_English_constraints', 5),
    ('grade10-weishi2026-21cnjy25962499', 'grammar', 'When he was 6 years', '\n三、书面表达', list(range(36, 46)), 'underscored', 'gapped_material_with_given_words', 10),
    ('grade10-weishi2026-21cnjy25962499', 'continuation', 'Lena had always', '\n注意：1．续写', [], None, 'continuation_reading_material', 1),
    ('grade11-heze2026-21cnjy24886046', 'grammar', 'To promote various', '\n第三节 单词拼写', list(range(56, 66)), 'suffix', 'gapped_material_with_given_words', 10),
    ('grade11-heze2026-21cnjy24886046', 'continuation', 'As the next school', '\n注 意 ：1.', [], None, 'continuation_reading_material', 1),
    ('grade12-linyi2025-21cnjy24838709', 'grammar', 'In and around China', '\n第四部分 写作', list(range(36, 46)), 'underscored', 'gapped_material_with_given_words', 10),
    ('grade12-linyi2025-21cnjy24838709', 'continuation', 'When my husband', '\n注意：', [], None, 'continuation_reading_material', 1),
]


def profiles():
    manifest = json.loads(CURRENT_BATCHES.read_text())
    papers = {p['id']: p for ref in manifest['batches'] for p in json.loads(load_ref(ref).read_text())['papers']}
    records = []
    for pid, local, start, end, ids, style, role, units in CASES:
        paper = papers[pid]
        text = load_ref(paper['resource_text']).read_text()
        begin = text.index(start)
        finish = text.index(end, begin)
        view = text[begin:finish].strip()
        offsets = []
        for number in ids:
            pattern = {'bare': r'\b' + str(number) + r'\b',
                       'underscored': r'_+' + str(number) + r'_+',
                       'line_labels': r'^' + str(number) + r'\.',
                       'suffix': r'\b' + str(number) + r'\.[_ ]+'}[style]
            found = list(re.finditer(pattern, view, re.M))
            if len(found) != 1:
                raise ValueError('Explicit source label not unique: ' + pid + '/' + str(number))
            offsets.append((found[0].start(), found[0].end(), number))
        if [n for _, _, n in sorted(offsets)] != ids:
            raise ValueError('Source response order changed')
        measured = view
        for first, last, _ in sorted(offsets, reverse=True):
            measured = measured[:first] + measured[last:]
        shape = next(r['shape'] for r in paper['rows'] if r['id'] == pid + '.' + local)
        if role == 'shared_word_bank':
            if len(view.split()) != units or shape['details']['entries'] != units:
                raise ValueError('Bank cardinality changed')
        elif ids and shape['responses'] != len(ids):
            raise ValueError('Response count does not match the source group')
        records.append({'group_id': pid + '.' + local, 'grade': paper['grade'],
                        'source_acquisition_id': paper['acquisition_id'], 'source_text': paper['resource_text'],
                        'component_role': role, 'component_units': units,
                        'source_line_span_1based': [text[:begin].count('\n') + 1, text[:finish].count('\n') + 1],
                        'component_sha256': hashlib.sha256(view.encode()).hexdigest(),
                        'removed_label_offsets': sorted(offsets), 'counts': count(measured),
                        'source_shape': shape, 'output_word_target_is_separate': True,
                        'English_token_count_not_full_input_load': True, 'student_minutes': None})
    return {'version': '0.1', 'scope': 'twelve_selected_non_MC_reading_component_views',
            'records': records, 'no_new_source_groups_or_authored_items': True, 'model_called': False}


if __name__ == '__main__':
    data = profiles()
    output = REPO / 'build/english-benchmark-research-20261012/nonreading-component-load20261015c-v0.1.json'
    payload = json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    if output.exists() and output.read_text() != payload:
        raise ValueError('Do not overwrite a different component profile')
    if not output.exists():
        output.write_text(payload)
    print(json.dumps([{'grade': r['grade'], 'group': r['group_id'].split('.')[-1],
                       'role': r['component_role'], 'tokens': r['counts']['english_digit_tokens']} for r in data['records']]))
