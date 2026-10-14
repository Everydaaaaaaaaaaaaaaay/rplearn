#!/usr/bin/env python3
"""Bind shared material and heterogeneous response rules to reviewed source spans."""
import argparse
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, material_text, remove_offsets

MANIFEST = BASE / 'FirstRelease/Sampling/multitask-material-views-v0.1.json'


def word_rule(text):
    match = re.search(r'(?:[Nn]o more than|不超过)\s*(\d+)\s*(?:words?|个?词)', text)
    if match:
        return {'operator': 'max', 'words': int(match[1])}
    match = re.search(r'仅填\s*(\d+)\s*词|[(（]\s*(\d+)\s*word', text)
    return {'operator': 'exact', 'words': int(match[1] or match[2])} if match else None


def layouts():
    rows = {r['id']: r for r in evidence()}
    result = {}
    for case in json.loads(MANIFEST.read_text())['views']:
        row = rows[case['group_id']]
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Task source differs from structural record')
        view = load_ref(case['source_text']).read_text()
        material = material_text(case, view)
        remove_offsets(material, case['excluded_offsets'], ' ')
        components = case['components']
        for c in components:
            text = view[c['start_offset']:c['end_offset']]
            if digest(text) != c['sha256'] or '【答案】' in text or '【解析】' in text:
                raise ValueError('Changed or private student component')
            remove_offsets(text, c.get('excluded_offsets', []))
        shared = [c for c in components if c['role'] == 'shared_option']
        details = row['shape']['details']
        if len(shared) != details.get('shared_options', 0) or [c['option_label'] for c in shared] != list('ABCDEFG'[:len(shared)]):
            raise ValueError('Shared candidates differ from actual source')
        if any(not view[c['start_offset']:c['end_offset']].startswith(c['option_label'] + '.') for c in shared):
            raise ValueError('Shared option label differs from source text')
        units, used = [], []
        for ordinal, u in enumerate(case['units'], 1):
            if u['ordinal'] != ordinal or u['response_units'] != 1:
                raise ValueError('Response ordinals or unit counts differ')
            index = u['student_location']
            c = components[index]
            number = u['printed_question_number']
            if c.get('source_question_number', c.get('source_slot_number')) != number:
                # Nanshan profiles print1-5 then separately numbered answer controls26-30.
                if 'response_control_component' not in u:
                    raise ValueError('Response number differs from source location')
                control = components[u['response_control_component']]
                if control['source_question_number'] != number or not view[control['start_offset']:control['end_offset']].startswith(str(number) + '.'):
                    raise ValueError('Response control number differs')
            if u['mode'] == 'word_completion':
                instructions = ' '.join(view[c['start_offset']:c['end_offset']] for c in components if c['role'] == 'student_instruction')
                if '一空一词（含缩写词）' not in instructions or u['word_rule'] != {'operator': 'exact', 'words': 1, 'contractions_allowed': True}:
                    raise ValueError('Open dialogue contraction/word policy differs')
            elif u['word_rule'] != word_rule(view[c['start_offset']:c['end_offset']]):
                raise ValueError('Per-response word count/operator differs from printed requirement')
            used.append(index)
            units.append(dict(u, student_location=c))
        if len(units) != row['shape']['responses'] or len(set(used)) != len(used):
            raise ValueError('Response positions missing or repeated')
        primary_slots = [u for u in units if u['student_location']['role'] == 'response_slot' and any(
            s['start_offset'] <= u['student_location']['start_offset'] < u['student_location']['end_offset'] <= s['end_offset']
            for s in case['material_segments'])]
        primary_slots.sort(key=lambda u: u['student_location']['start_offset'])
        if ([u['printed_question_number'] for u in primary_slots] != case['expected_blank_ids'] or
                [u['ordinal'] for u in primary_slots] != case['material_blank_response_ordinals']):
            raise ValueError('Primary blanks assigned to a different mixed response unit')
        tables = [c for c in components if c['role'] == 'required_table_text']
        table_slots = [u['student_location'] for u in units if u['mode'] == 'table_fill']
        if table_slots and (len(tables) != 1 or any(not tables[0]['start_offset'] <= c['start_offset'] < c['end_offset'] <= tables[0]['end_offset'] for c in table_slots)):
            raise ValueError('Table response lacks its required source table')
        if 'components' in details:
            expected_modes = [c['mode'] for c in details['components'] for _ in range(c['responses'])]
            if [u['mode'] for u in units] != expected_modes:
                raise ValueError('Mixed subgroups differ from source structure')
        if 'per_response_word_limits' in details and [u['word_rule']['words'] for u in units] != details['per_response_word_limits']:
            raise ValueError('Word limits differ from structural observations')
        required = [c for c in components if c['role'] in ['required_table_text', 'shared_option', 'given_Chinese_hint', 'response_control_row']]
        result[row['id']] = {'source_shape': row['shape'], 'source_text': case['source_text'],
                             'material_sha256': digest(material), 'response_units': len(units),
                             'units': units, 'required_student_components': required,
                             'reuse_rule': details.get('reuse_rule'), 'explicit_spare': details.get('explicit_spare'),
                             'response_policy': details.get('response_policy'),
                             'necessary_input_complete': row['necessary_input_complete'],
                             'source_risks': case['source_defects']}
    return result


def check(request, available):
    gid = request.get('evidence_group_id')
    if gid not in available or request.get('layout') != available[gid]:
        raise ValueError('Material/subgroup/response/word-rule/shared-input/source-policy binding differs')
    state = available[gid]['necessary_input_complete']
    if request.get('requires_complete_student_input', True) and state is not True:
        raise ValueError('Necessary source input missing or unconfirmed')
    if request.get('use_as_verified_answer_gold') or request.get('claim_production_supported'):
        raise ValueError('Task layout is not independent answer gold or production support')
    return {'source_task_layout_matches': True, 'evidence_group_id': gid,
            'response_units': available[gid]['response_units'], 'necessary_input_complete': state,
            'content_semantics_checked': False, 'independent_gold': False, 'model_called': False,
            'production_supported': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.request.read_text()), layouts()), ensure_ascii=False))
