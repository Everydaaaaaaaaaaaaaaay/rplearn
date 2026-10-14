#!/usr/bin/env python3
"""Measure seven explicitly bounded cloze materials; no grade thresholds.

Counts refer to the public text view, not original typography or student time.
Question numbers/option labels and answer explanations are outside material spans.
"""
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, BATCH, load_ref
from profile_task_load import count

CASES = [
    (7, 'grade7-suzhou2025-21cnjy23303742', 'cloze', 'In the great outdoors', '\n1. A. words', list(range(1, 11)), 'underscored'),
    (8, 'grade8-xiaoshan2025-21cnjy22251031', 'cloze', 'Our classroom was filled', '\n36. A. coach', list(range(36, 51)), 'bare_numbers'),
    (9, 'grade9-chengdu2025-21cnjy23208601', 'clozeA', 'On Sunday, Mum and Dad', '\n16. A. confident', list(range(16, 21)), 'underscored'),
    (9, 'grade9-chengdu2025-21cnjy23208601', 'clozeB', 'Living in a new country', '\n21. A. lessons', list(range(21, 31)), 'underscored'),
    (10, 'grade10-shenzhenlower2026-21cnjy26167651', 'cloze', 'I have always believed', '\n41. A. bring out', list(range(41, 56)), 'bare_numbers'),
    (11, 'grade11-yinchuan2026-21cnjy25860535', 'cloze', 'Sometimes a rescue', '\n21. A. skill', list(range(21, 36)), 'underscored'),
    (12, 'grade12-tianjin2025-21cnjy24812550', 'cloze', 'Jimmy is an automotive', '\n16. A. task', list(range(16, 36)), 'underscored'),
]


if __name__ == '__main__':
    batch = json.loads(BATCH.read_text())
    rows = []
    for grade, pid, local, start, end, ids, style in CASES:
        paper = next(x for x in batch['papers'] if x['id'] == pid)
        source = load_ref(paper['resource_text'])
        text = source.read_text()
        first = text.index(start)
        last = text.index(end, first)
        passage = text[first:last].strip()
        spans = []
        for number in ids:
            pattern = (r'_+' + str(number) + r'_+') if style == 'underscored' else r'\b' + str(number) + r'\b'
            found = list(re.finditer(pattern, passage))
            if len(found) != 1:
                raise ValueError('Blank location not unique: ' + pid + '/' + str(number))
            spans += [(m.start(), m.end(), number) for m in found]
        if [n for _, _, n in sorted(spans)] != ids:
            raise ValueError('Blank order differs')
        without_blanks = passage
        for begin, finish, _ in sorted(spans, reverse=True):
            without_blanks = without_blanks[:begin] + without_blanks[finish:]
        observation = next(x for x in paper['rows'] if x['id'].endswith('.' + local))
        if observation['shape']['responses'] != len(ids):
            raise ValueError('Source quantity differs')
        rows.append({'grade': grade, 'group_id': observation['id'], 'paper_identity': pid,
                     'source_acquisition_id': paper['acquisition_id'], 'source_text': paper['resource_text'],
                     'source_line_span_1based': [text[:first].count('\n') + 1, text[:last].count('\n') + 1],
                     'material_span_sha256': hashlib.sha256(passage.encode()).hexdigest(),
                     'counted_unfilled_material': count(without_blanks),
                     'responses': len(ids), 'options_each': observation['shape']['options_each'],
                     'blank_number_ids': ids, 'blank_offsets_in_text_view': sorted(spans),
                     'role': 'material_only_no_question_option_instruction_or_answer_count',
                     'printed_English_in_parenthetical_glosses_retained': True,
                     'filled_answer_count': None, 'student_minutes': None,
                     'national_typical_length_or_grade_threshold': None})
    output = REPO / 'build/english-benchmark-research-20261012/cloze-volume-batch20261015-v0.1.json'
    output.write_text(json.dumps({'version': '0.1', 'token_rule': 'profile_task_load.count; exclude explicitly verified blank number spans only',
                                  'records': rows}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps([{'grade': x['grade'], 'group': x['group_id'], 'responses': x['responses'],
                      'material_tokens': x['counted_unfilled_material']['english_digit_tokens']} for x in rows], ensure_ascii=False))
