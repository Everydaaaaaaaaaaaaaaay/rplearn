#!/usr/bin/env python3
"""Correct selected comparison views without overwriting frozen material audits."""
import argparse
import json
import re
from pathlib import Path

from grade_mode_evidence import BASE, REPO, evidence, load_ref
from rank_material_overlap import current_bodies, reference
from audit_school_material_families import digest, material_text, remove_offsets, normalize_view
from audit_baseline_bank_forms import compare
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/material-view-corrections-v0.2.json'


def apply_corrections(manifest, bodies):
    corrected = dict(bodies)
    sources = {row['id']: row for row in evidence()}
    atomic = json.loads(load_ref(manifest['existing_atomic_sentence_audit']).read_text())
    details = []
    for correction in manifest['corrections']:
        gid = correction['group_id']
        if gid in {row['group_id'] for row in details} or gid not in bodies:
            raise ValueError('Repeated or missing corrected source')
        source = sources[gid]
        if (source['shape']['family'] != 'sentence_translation' or correction['normalization'] != 'bilingual_token_view' or
                digest(bodies[gid]) != correction['old_normalized_material_sha256']):
            raise ValueError('Correction source, language policy or frozen view differs')
        views = json.loads(load_ref(correction['source_view_manifest']).read_text())['views']
        case = next(row for row in views if row['group_id'] == gid)
        if source['source_text_ref'] != case['source_text']:
            raise ValueError('Correction belongs to another source text')
        raw = load_ref(case['source_text']).read_text()
        measured = remove_offsets(material_text(case, raw), case['excluded_offsets'], ' ')
        norm = normalize_view(measured, correction['normalization'])
        atoms = [row for row in atomic['records'] if row['group_id'] == gid]
        if (correction['responses'] != source['shape']['responses'] or len(case['items']) != correction['responses'] or
                len(atoms) != correction['responses'] or len(case['material_segments']) != correction['responses']):
            raise ValueError('Correction must retain every source translation unit')
        for ordinal, (item, segment, old_atom) in enumerate(zip(case['items'], case['material_segments'], atoms), 1):
            component = next(c for c in case['components'] if c['role'] == 'prompt_with_hints' and c['item_id'] == ordinal)
            text = raw[segment['start_offset']:segment['end_offset']]
            if item['ordinal'] != ordinal or digest(text) != segment['sha256'] or old_atom['ordinal'] != ordinal:
                raise ValueError('Translation source order or atomic identity differs')
            text = remove_offsets(text, component['excluded_offsets'], ' ')
            if digest(normalize_view(text, 'bilingual_token_view')) != old_atom['bilingual_normalized_prompt_sha256']:
                raise ValueError('Corrected item differs from prior bilingual atomic evidence')
        counts = count(measured)
        if (counts['han_characters'] != correction['preserved_Han_characters'] or
                counts['english_digit_tokens'] != correction['preserved_English_digit_tokens'] or
                len(re.findall('[\u4e00-\u9fff]', norm)) != counts['han_characters'] or
                digest(norm) != correction['corrected_normalized_material_sha256']):
            raise ValueError('Correction loses Chinese prompts or changes source content')
        corrected[gid] = norm
        details.append({'group_id': gid, 'source_text': case['source_text'], 'responses': correction['responses'],
                        'old_normalized_material_sha256': digest(bodies[gid]),
                        'normalized_material_sha256': digest(norm), 'corrected_normalized_material': norm,
                        'source_counts': counts, 'prior_atomic_records_reused': len(atoms),
                        'frozen_source_necessary_input_complete': source['necessary_input_complete']})
    return corrected, details


def corrected_bodies():
    bodies, _ = current_bodies()
    manifest = json.loads(MANIFEST.read_text())
    return apply_corrections(manifest, bodies)


def audit(manifest_path=MANIFEST):
    manifest_path = manifest_path.resolve()
    bodies, _ = current_bodies()
    manifest = json.loads(manifest_path.read_text())
    prior = json.loads(load_ref(manifest['prior_group_audit']).read_text())
    inventory = json.loads(load_ref(manifest['prior_inventory']).read_text())
    if inventory['current_audit'] != manifest['prior_group_audit'] or len(bodies) != prior['material_count_total']:
        raise ValueError('Correction does not extend the declared inventory')
    corrected, records = apply_corrections(manifest, bodies)
    changed = {row['group_id'] for row in records}
    comparisons, removed_exact, removed_candidates = [], 0, 0
    ids = list(bodies)
    for i, left in enumerate(ids):
        for right in ids[i + 1:]:
            if left not in changed and right not in changed:
                continue
            old = compare(bodies[left], bodies[right])
            new = compare(corrected[left], corrected[right])
            removed_exact += old['exact_normalized_match']
            removed_candidates += old['review_candidate']
            comparisons.append({'left': left, 'right': right, **new})
    return {'version': '0.1', 'scope': 'replacement of affected comparison pairs;not new source material',
            'correction_manifest': reference(manifest_path), 'prior_records_and_comparisons': manifest['prior_group_audit'],
            'records': records, 'material_count_total': len(bodies), 'parent_count_total': prior['parent_count_total'],
            'pair_count_total': prior['pair_count_total'], 'unaffected_pairs_reused': prior['pair_count_total'] - len(comparisons),
            'old_affected_pairs_checked': len(comparisons), 'replacement_pair_count': len(comparisons),
            'comparisons': comparisons,
            'exact_repeat_pairs': prior['exact_repeat_pairs'] - removed_exact + sum(r['exact_normalized_match'] for r in comparisons),
            'review_candidates': prior['review_candidates'] - removed_candidates + sum(r['review_candidate'] for r in comparisons),
            'source_records_or_response_positions_added': 0, 'original_source_or_frozen_report_overwritten': False,
            'all_semantic_visual_screening_complete': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--manifest', type=Path, default=MANIFEST)
    args = parser.parse_args()
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Source-derived output must remain in ignored build/')
    result = audit(args.manifest)
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Do not overwrite a different correction report')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({key: result[key] for key in ['material_count_total', 'parent_count_total', 'pair_count_total',
                                                  'unaffected_pairs_reused', 'replacement_pair_count', 'review_candidates']}))
