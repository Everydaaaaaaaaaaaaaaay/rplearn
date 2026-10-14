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


def remove_offsets(text, offsets, separator=''):
    last = 0
    for row in sorted(offsets, key=lambda r: r['start']):
        start, end = row['start'], row['end']
        if not last <= start < end <= len(text) or text[start:end] != row['literal']:
            raise ValueError('Overlapping or changed exclusion')
        last = end
    for row in sorted(offsets, key=lambda r: r['start'], reverse=True):
        text = text[:row['start']] + separator + text[row['end']:]
    return text


def material_text(case, view):
    """Read a continuous passage or ordered student prompts in an interleaved repost."""
    start, end = case['start_offset'], case['end_offset']
    envelope = view[start:end]
    if not 0 <= start < end <= len(view) or digest(envelope) != case['material_sha256']:
        raise ValueError('Changed material span')
    if 'material_segments' not in case:
        return envelope
    parts, previous_end = [], start
    for segment in case['material_segments']:
        a, b = segment['start_offset'], segment['end_offset']
        text = view[a:b]
        if not previous_end <= a < b <= end or digest(text) != segment['sha256']:
            raise ValueError('Changed or overlapping student material segment')
        parts.append(text)
        previous_end = b
    material = '\n'.join(parts)
    if not parts or digest(material) != case['assembled_material_sha256']:
        raise ValueError('Changed assembled student material')
    return material


def audit(manifest):
    layers, seen = [manifest], set()
    while layers[-1].get('prior_view_manifest'):
        ref = layers[-1]['prior_view_manifest']
        identity = (ref['path'], ref['sha256'])
        if identity in seen:
            raise ValueError('Repeated/cyclic material view ancestry')
        seen.add(identity)
        layers.append(json.loads(load_ref(ref).read_text()))
    frozen = layers[-1]['frozen_nineteen_audit']
    if any(layer.get('frozen_nineteen_audit', frozen) != frozen for layer in layers):
        raise ValueError('Different frozen material baselines')
    old = json.loads(load_ref(frozen).read_text())
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
    for case in [case for layer in reversed(layers) for case in layer['views']]:
        row = by_id[case['group_id']]
        view = load_ref(case['source_text']).read_text()
        if row.get('source_text_ref') != case['source_text']:
            raise ValueError('Material belongs to a different source')
        material = material_text(case, view)
        blanks = [r for r in case['excluded_offsets'] if r['role'] == 'blank_label']
        if case['expected_blank_ids'] != [r['blank_id'] for r in sorted(blanks, key=lambda r: r['start'])]:
            raise ValueError('Blank sequence differs')
        if blanks and len(blanks) != row['shape']['responses']:
            raise ValueError('Blank count differs from shape')
        measured = remove_offsets(material, case['excluded_offsets'],
                                  ' ' if case.get('replace_exclusions_with_space') else '')
        norm = normalized(measured)
        components = {}
        for component in case.get('components', []):
            text = view[component['start_offset']:component['end_offset']]
            if digest(text) != component['sha256']:
                raise ValueError('Changed companion component')
            content = remove_offsets(text, component.get('excluded_offsets', []),
                                     ' ' if component.get('replace_exclusions_with_space') else '')
            totals = components.setdefault(component['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for key, value in count(content).items():
                totals[key] += value
            totals['components'] += 1
        if (row['shape']['family'] == 'reading_choice' and not case.get('components') and
                case.get('reviewed_material_only_not_component_profile') is not True):
            raise ValueError('Material-only reading view must explicitly declare its limited scope')
        if row['shape']['family'] == 'reading_choice' and case.get('components'):
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
                     'reading_text_component_allocation_present': row['shape']['family'] == 'reading_choice' and bool(case.get('components')),
                     'necessary_student_input_complete': row['necessary_input_complete'],
                     'comparison_scope': case['comparison_scope'], 'source_defects': case['source_defects'],
                     'independent_answer_gold': False, 'student_minutes': None})
        if case['group_id'] in bodies:
            raise ValueError('Repeated material view')
        bodies[case['group_id']] = norm
    prior_ids, prior_pair_count = set(), 0
    prior_exact = prior_candidates = 0
    if manifest.get('prior_material_audit'):
        previous = json.loads(load_ref(manifest['prior_material_audit']).read_text())
        current = {r['group_id']: r for r in rows}
        for earlier in previous['records']:
            gid = earlier['group_id']
            if gid in prior_ids or gid not in current:
                raise ValueError('Duplicate or missing prior material')
            for key in ['material_sha256', 'normalized_material_sha256', 'material_counts', 'companion_counts']:
                if key in earlier and earlier[key] != current[gid].get(key):
                    raise ValueError('Prior material changed; cannot reuse comparisons')
            prior_ids.add(gid)
        prior_pair_count = previous.get('pair_count_total', len(previous['comparisons']))
        if prior_pair_count != len(prior_ids) * (len(prior_ids) - 1) // 2:
            raise ValueError('Prior comparison coverage differs')
        prior_exact = previous['exact_repeat_pairs']
        prior_candidates = previous['review_candidates']
    comparisons = []
    for left, right in combinations(bodies, 2):
        if left in prior_ids and right in prior_ids:
            continue
        a, b = shingles(bodies[left]), shingles(bodies[right])
        jaccard = len(a & b) / len(a | b) if a | b else 0
        containment = len(a & b) / min(len(a), len(b)) if a and b else 0
        comparisons.append({'left': left, 'right': right,
                            'exact_normalized_match': bodies[left] == bodies[right],
                            'fivegram_jaccard': jaccard, 'fivegram_containment': containment,
                            'review_candidate': bodies[left] == bodies[right] or jaccard >= .5 or containment >= .8})
    total_pairs = len(rows) * (len(rows) - 1) // 2
    if len(comparisons) + prior_pair_count != total_pairs:
        raise ValueError('Incremental comparison coverage differs')
    result = {'version': '0.2' if prior_pair_count else '0.1', 'scope': manifest['scope'], 'records': rows, 'comparisons': comparisons,
            'frozen19_reproduced': True, 'exact_repeat_pairs': prior_exact + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior_candidates + sum(c['review_candidate'] for c in comparisons),
            'screen_threshold_not_validated_plagiarism_or_family_classifier': True,
            'zero_candidates_not_proof_of_independent_origins': True,
            'normalization_limits': ['English/digit token view ignores Chinese glosses and punctuation',
                                     'Declared blanks/labels removed; source spelling defects remain',
                                     'No semantic paraphrase detection or whole-library independence claim'],
            'all_benchmark_deduplication_complete': False, 'model_called': False}
    if prior_pair_count:
        result.update(prior_material_audit=manifest['prior_material_audit'], prior_pairs_reused=prior_pair_count,
                      pair_count_total=total_pairs, new_pair_count=len(comparisons))
    return result


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
                      'pairs': result.get('pair_count_total', len(result['comparisons'])),
                      'new_pairs': result.get('new_pair_count', len(result['comparisons'])),
                      'prior_pairs_reused': result.get('prior_pairs_reused', 0), 'exact_repeat_pairs': result['exact_repeat_pairs'],
                      'review_candidates': result['review_candidates'], 'frozen19_reproduced': True}))
