#!/usr/bin/env python3
"""Check source-bound nonreading input layout, not meaning, gold or production."""
import argparse
import json
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref

MANIFEST = BASE / 'FirstRelease/Sampling/nonreading-material-views-v0.1.json'


def layouts():
    data = json.loads(MANIFEST.read_text())
    sources = {r['id']: r for r in evidence()}
    result = {}
    for case in data['views']:
        row = sources[case['group_id']]
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Layout source differs from structural source')
        view = load_ref(case['source_text']).read_text()
        from audit_school_material_families import digest, remove_offsets
        material = view[case['start_offset']:case['end_offset']]
        if digest(material) != case['material_sha256']:
            raise ValueError('Changed source material')
        remove_offsets(material, case['excluded_offsets'])
        ids = case['expected_blank_ids']
        observed = [r['blank_id'] for r in sorted(case['excluded_offsets'], key=lambda r: r['start']) if r['role'] == 'blank_label']
        if observed != ids or len(ids) != row['shape']['responses']:
            raise ValueError('Layout blank positions differ from structural record')
        hint_ordinals = [ids.index(n) + 1 for n in (case.get('observed_given_hint_slots') or [])]
        unknown = [ids.index(n) + 1 for n in case.get('unknown_hint_or_given_state_slots', [])]
        roles = []
        for component in case['components']:
            text = view[component['start_offset']:component['end_offset']]
            if digest(text) != component['sha256']:
                raise ValueError('Changed shared input or hint')
            remove_offsets(text, component.get('excluded_offsets', []))
            roles.append(component['role'])
        if row['shape']['family'] == 'passage_form':
            hint_components = [c for c in case['components'] if c['role'] == 'given_hints']
            if [c['blank_id'] for c in hint_components] != case['observed_given_hint_slots']:
                raise ValueError('Hint positions disagree with actual source components')
            blank_labels = [e for e in case['excluded_offsets'] if e['role'] == 'blank_label']
            for component in hint_components:
                label = next(e for e in blank_labels if e['blank_id'] == component['blank_id'])
                gap = material[label['end']:component['start_offset'] - case['start_offset']]
                if gap.strip() or component['start_offset'] < case['start_offset'] + label['end']:
                    raise ValueError('Given hint is not adjacent to its declared source blank')
            fragment_slots = []
            for component in [c for c in case['components'] if c['role'] == 'unresolved_source_fragment']:
                position = component['start_offset'] - case['start_offset']
                adjacent = [e for e in blank_labels if e['end'] <= position and not material[e['end']:position].strip()]
                if len(adjacent) != 1:
                    raise ValueError('Unresolved hint fragment lacks an unambiguous source slot')
                fragment_slots.append(adjacent[0]['blank_id'])
            if fragment_slots != case.get('unknown_hint_or_given_state_slots', []):
                raise ValueError('Unknown hint state differs from source fragment location')
        details, family = row['shape']['details'], row['shape']['family']
        bank = case.get('source_bank_entries_observed')
        if bank is not None:
            shared = next(c for c in case['components'] if c['role'] == 'shared_bank')
            source_bank = view[shared['start_offset']:shared['end_offset']]
            if len(bank) != details['entries'] or any(entry not in source_bank for entry in bank):
                raise ValueError('Observed bank entries differ from source/count')
        layout = {'source_shape': row['shape'], 'grade': row['shape']['grade'], 'family': family, 'responses': len(ids),
                  'materials': case.get('material_count_observed', details.get('materials')), 'options_each': row['shape']['options_each'],
                  'shared_entries': details.get('entries') if family == 'shared_bank' else details.get('shared_options'),
                  'shared_input_present': ('shared_bank' in roles if family == 'shared_bank' else 'shared_options' in roles if family == 'shared_insertion' else None),
                  'source_bank_entries': bank if family == 'shared_bank' else None,
                  'given_hint_ordinals': hint_ordinals if family == 'passage_form' else None,
                  'unknown_hint_or_given_state_ordinals': unknown if family == 'passage_form' else None,
                  'ungiven_ordinals': [n for n in range(1, len(ids) + 1) if n not in hint_ordinals + unknown] if family == 'passage_form' else None,
                  'response_policy': details.get('response_policy'), 'form_policy': details.get('form_policy'),
                  'reuse_rule': details.get('reuse_rule'), 'explicit_spare': details.get('explicit_spare'),
                  'necessary_input_complete': row['necessary_input_complete'],
                  'material_sha256': case['material_sha256'], 'source_text': case['source_text']}
        result[row['id']] = layout
    return result


def check(request, available):
    gid = request.get('evidence_group_id')
    if gid not in available:
        raise ValueError('No observed nonreading layout for this group')
    expected = available[gid]
    if json.dumps(request.get('layout'), sort_keys=True) != json.dumps(expected, sort_keys=True):
        raise ValueError('Grade/material/hint/shared-candidate/rule layout differs from this source')
    if request.get('requires_complete_student_input', True) and expected['necessary_input_complete'] is not True:
        raise ValueError('Necessary input is missing or not explicitly confirmed')
    if request.get('use_as_verified_answer_gold') or request.get('claim_production_supported'):
        raise ValueError('Layout binding is not answer gold or production support')
    return {'source_layout_matches': True, 'evidence_group_id': gid,
            'necessary_input_complete': expected['necessary_input_complete'],
            'content_semantics_checked': False, 'independent_gold': False, 'production_supported': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.request.read_text()), layouts()), ensure_ascii=False))
