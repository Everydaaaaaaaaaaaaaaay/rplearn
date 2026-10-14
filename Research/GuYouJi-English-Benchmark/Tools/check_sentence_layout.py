#!/usr/bin/env python3
"""Bind isolated student tasks; visible blanks and selection responses differ."""
import argparse
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, material_text, remove_offsets

MANIFEST = BASE / 'FirstRelease/Sampling/sentence-material-views-v0.1.json'


def layouts():
    rows = {r['id']: r for r in evidence()}
    available = {}
    for case in json.loads(MANIFEST.read_text())['views']:
        row = rows[case['group_id']]
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Sentence layout belongs to another source')
        view = load_ref(case['source_text']).read_text()
        material = material_text(case, view)
        remove_offsets(material, case['excluded_offsets'], ' ')
        components = case['components']
        for component in components:
            text = view[component['start_offset']:component['end_offset']]
            if digest(text) != component['sha256'] or '【答案】' in text or '【解析】' in text:
                raise ValueError('Changed student component or leaked private explanation')
            remove_offsets(text, component.get('excluded_offsets', []))
        if len(case['items']) != row['shape']['responses'] or len(case['material_segments']) != len(case['items']):
            raise ValueError('Student response count differs from source')
        units, used_options, used_hints = [], [], []
        for ordinal, item in enumerate(case['items'], 1):
            if item['ordinal'] != ordinal or item['response_units'] != 1 or item['prompt_segment'] != ordinal - 1:
                raise ValueError('Source item must remain one ordered response unit')
            prompt = case['material_segments'][item['prompt_segment']]
            prompt_components = [c for c in components if c['role'] == 'prompt_with_hints' and c['item_id'] == ordinal]
            if len(prompt_components) != 1 or any(prompt_components[0][k] != prompt[k] for k in ['start_offset', 'end_offset', 'sha256']):
                raise ValueError('Measured prompt component differs from its student segment')
            text = view[prompt['start_offset']:prompt['end_offset']]
            number = item['printed_question_number']
            if number is not None and not re.match(r'^' + str(number) + r'\.', text):
                raise ValueError('Source question number differs')
            indices = item['option_components']
            options = [components[i] for i in indices]
            if len(options) != (row['shape']['options_each'] or 0):
                raise ValueError('Per-item options differ from observed source')
            if [c.get('option_label') for c in options] != list('ABCD'[:len(options)]):
                raise ValueError('Missing or reordered source option labels')
            if any(c['role'] != 'option' or c['item_id'] != ordinal for c in options):
                raise ValueError('Option assigned to another student item')
            if any(c['start_offset'] < prompt['end_offset'] or
                   (ordinal < len(case['items']) and c['end_offset'] > case['material_segments'][ordinal]['start_offset']) for c in options):
                raise ValueError('Option falls outside its source item')
            used_options.extend(indices)
            initials, previous_end = [], prompt['start_offset']
            for blank in item['visible_blanks']:
                a, b = blank['start_offset'], blank['end_offset']
                raw = view[a:b]
                if not previous_end <= a < b <= prompt['end_offset'] or digest(raw) != blank['sha256']:
                    raise ValueError('Changed visible blank position')
                if blank['printed_initial'] is not None:
                    if raw[0] != blank['printed_initial'] or (a > 0 and view[a - 1].isalpha()):
                        raise ValueError('Word-final character is not a printed initial hint')
                previous_end = b
                initials.append(blank['printed_initial'])
            hint_indices = item['hint_components']
            hints = [components[i] for i in hint_indices]
            if any(c['item_id'] != ordinal or not prompt['start_offset'] <= c['start_offset'] < c['end_offset'] <= prompt['end_offset'] for c in hints):
                raise ValueError('Hint assigned to another source prompt')
            used_hints.extend(hint_indices)
            units.append({'ordinal': ordinal, 'printed_question_number': number,
                          'response_units': 1, 'options_each': len(options),
                          'visible_blank_count': len(item['visible_blanks']),
                          'printed_initials': initials,
                          'given_form_hint_count': sum(c['role'] == 'given_form_hint' for c in hints),
                          'hint_roles': [c['role'] for c in hints], 'source_risks': item['source_risks']})
        if sorted(used_options) != [i for i, c in enumerate(components) if c['role'] == 'option'] or len(set(used_options)) != len(used_options):
            raise ValueError('Source choices omitted or assigned twice')
        if sorted(used_hints) != [i for i, c in enumerate(components) if c['role'] in ['given_form_hint', 'translation_constraint', 'Chinese_hint_or_gloss']]:
            raise ValueError('Source hints omitted or assigned twice')
        details = row['shape']['details']
        if 'given_word_slots' in details and sum(u['given_form_hint_count'] for u in units) != details['given_word_slots']:
            raise ValueError('Given-form slot count differs')
        available[row['id']] = {'source_shape': row['shape'], 'source_text': case['source_text'],
                                'material_sha256': digest(material), 'response_units': len(units),
                                'units': units, 'necessary_input_complete': row['necessary_input_complete'],
                                'response_policy': details.get('response_policy'),
                                'initial_vs_suffix_scoring_unknown': details.get('initial_vs_suffix_scoring_unknown'),
                                'reference_contains_multiword_forms': details.get('reference_contains_multiword_forms'),
                                'whole_sentence_outputs': details.get('whole_sentence_outputs')}
    return available


def check(request, available):
    gid = request.get('evidence_group_id')
    if gid not in available or request.get('layout') != available[gid]:
        raise ValueError('Sentence response/option/blank/hint/policy layout differs from source')
    if request.get('requires_complete_student_input', True) and available[gid]['necessary_input_complete'] is not True:
        raise ValueError('Source input missing or not explicitly confirmed')
    if request.get('use_as_verified_answer_gold') or request.get('claim_production_supported'):
        raise ValueError('Sentence layout does not establish gold or production support')
    return {'source_sentence_layout_matches': True, 'evidence_group_id': gid,
            'response_units': available[gid]['response_units'],
            'necessary_input_complete': available[gid]['necessary_input_complete'],
            'independent_gold': False, 'production_supported': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.request.read_text()), layouts()), ensure_ascii=False))
