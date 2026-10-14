#!/usr/bin/env python3
"""Compare explicitly bounded material views; partial views cannot prove independence.

Frozen nineteen cloze measurements are replayed. New spans retain source defects;
only declared blank/label offsets are removed from comparison, never arbitrary numbers.
"""
import argparse
import hashlib
import json
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_cloze_materials import normalized, shingles
from profile_task_load import count


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def remove_offsets(text, offsets):
    last = 0
    for row in sorted(offsets, key=lambda r: r['start']):
        start, end = row['start'], row['end']
        if not last <= start < end <= len(text) or text[start:end] != row['literal']:
            raise ValueError('Overlapping or changed exclusion')
        last = end
    for row in sorted(offsets, key=lambda r: r['start'], reverse=True):
        text = text[:row['start']] + text[row['end']:]
    return text


def audit(manifest):
    old = json.loads(load_ref(manifest['frozen_nineteen_audit']).read_text())
    rows, bodies = [], {}
    for record in old['records']:
        view = load_ref(record['source_text']).read_text()
        first, last = record['material_line_span_1based']
        material = '\n'.join(view.splitlines()[first - 1:last]).strip()
        if digest(material) != record['material_sha256']:
            raise ValueError('Frozen material boundary changed: ' + record['group_id'])
        offsets = [{'start': a, 'end': b, 'literal': material[a:b]}
                   for a, b, _ in record['blank_offsets_in_material']]
        measured = remove_offsets(material, offsets)
        norm = normalized(measured)
        if digest(norm) != record['normalized_material_sha256'] or count(measured) != record['material_counts']:
            raise ValueError('Frozen nineteen measurements differ')
        rows.append(dict(record, comparison_scope='complete_text_material_not_answer_or_rights',
                         frozen_measurement_reproduced=True))
        bodies[record['group_id']] = norm
    by_id = {r['id']: r for r in evidence()}
    for case in manifest['views']:
        row = by_id[case['group_id']]
        view = load_ref(case['source_text']).read_text()
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Material belongs to a different source')
        start, end = case['start_offset'], case['end_offset']
        material = view[start:end]
        if not 0 <= start < end <= len(view) or digest(material) != case['material_sha256']:
            raise ValueError('Changed material span')
        blanks = [r for r in case['excluded_offsets'] if r['role'] == 'blank_label']
        if case['expected_blank_ids'] != [r['blank_id'] for r in sorted(blanks, key=lambda r: r['start'])]:
            raise ValueError('Blank sequence differs')
        if blanks and len(blanks) != row['shape']['responses']:
            raise ValueError('Blank count differs from shape')
        measured = remove_offsets(material, case['excluded_offsets'])
        norm = normalized(measured)
        components = {}
        for component in case.get('components', []):
            text = view[component['start_offset']:component['end_offset']]
            if digest(text) != component['sha256']:
                raise ValueError('Changed companion component')
            content = remove_offsets(text, component.get('excluded_offsets', []))
            totals = components.setdefault(component['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for key, value in count(content).items():
                totals[key] += value
            totals['components'] += 1
        if row['shape']['family'] == 'reading_choice':
            prompts = [c for c in case['components'] if c['role'] == 'prompt']
            options = [c for c in case['components'] if c['role'] == 'option']
            ids = {c['item_id'] for c in prompts}
            if len(prompts) != row['shape']['responses'] or len(ids) != len(prompts):
                raise ValueError('Incomplete reading prompt allocation')
            if any(c['item_id'] not in ids for c in options) or any(
                    sum(c['item_id'] == i for c in options) != row['shape']['options_each'] for i in ids):
                raise ValueError('Incomplete reading option allocation')
            if row['necessary_input_complete'] is True and any(
                    not remove_offsets(view[c['start_offset']:c['end_offset']], c.get('excluded_offsets', [])).strip()
                    for c in options):
                raise ValueError('Empty option cannot support complete student input')
        rows.append({'group_id': case['group_id'], 'grade': row['shape']['grade'],
                     'paper_identity': row['paper_id'], 'source_text': case['source_text'],
                     'material_sha256': digest(material), 'normalized_material_sha256': digest(norm),
                     'material_counts': count(measured), 'companion_counts': components,
                     'excluded_label_counts': count(' '.join(r['literal'] for r in case['excluded_offsets']
                                                           if r['role'] == 'material_label')),
                     'responses': row['shape']['responses'], 'options_each': row['shape']['options_each'],
                     'necessary_student_input_complete': row['necessary_input_complete'],
                     'comparison_scope': case['comparison_scope'], 'source_defects': case['source_defects'],
                     'independent_answer_gold': False, 'student_minutes': None})
        if case['group_id'] in bodies:
            raise ValueError('Repeated material view')
        bodies[case['group_id']] = norm
    comparisons = []
    for left, right in combinations(bodies, 2):
        a, b = shingles(bodies[left]), shingles(bodies[right])
        jaccard = len(a & b) / len(a | b) if a | b else 0
        containment = len(a & b) / min(len(a), len(b)) if a and b else 0
        comparisons.append({'left': left, 'right': right,
                            'exact_normalized_match': bodies[left] == bodies[right],
                            'fivegram_jaccard': jaccard, 'fivegram_containment': containment,
                            'review_candidate': bodies[left] == bodies[right] or jaccard >= .5 or containment >= .8})
    return {'version': '0.1', 'scope': manifest['scope'], 'records': rows, 'comparisons': comparisons,
            'frozen19_reproduced': True, 'exact_repeat_pairs': sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': sum(c['review_candidate'] for c in comparisons),
            'screen_threshold_not_validated_plagiarism_or_family_classifier': True,
            'zero_candidates_not_proof_of_independent_origins': True,
            'normalization_limits': ['English/digit token view ignores Chinese glosses and punctuation',
                                     'Declared blanks/labels removed; source spelling defects remain',
                                     'No semantic paraphrase detection or whole-library independence claim'],
            'all_benchmark_deduplication_complete': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Raw-derived results must remain in ignored build/')
    result = audit(json.loads(args.manifest.read_text()))
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Refuse to overwrite a different audit')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({'materials': len(result['records']), 'parents': len({r['paper_identity'] for r in result['records']}),
                      'pairs': len(result['comparisons']), 'exact_repeat_pairs': result['exact_repeat_pairs'],
                      'review_candidates': result['review_candidates'], 'frozen19_reproduced': True}))
