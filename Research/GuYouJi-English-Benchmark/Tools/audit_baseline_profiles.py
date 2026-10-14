#!/usr/bin/env python3
"""Bind profile matching cards/images and preserve unspecified reuse rules."""
import argparse
import json
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_school_material_families import digest
from audit_cloze_materials import normalized
from audit_baseline_bank_forms import ancestor_materials, source_views as bank_views, compare
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-profile-material-views-v0.1.json'


def profile_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    records, bodies, atomic, layouts = [], {}, {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id'] or row['shape']['family'] != 'profile_matching':
            raise ValueError('Profile source layer/parent/mode differs')
        parent = acquisitions[case['source_parent_id']]
        if case['parent_document'] != {'path': parent['path'], 'sha256': parent['sha256']}:
            raise ValueError('Original parent version differs')
        load_ref(case['parent_document'])
        obs = next(r for r in json.loads(load_ref(case['source_catalogue']).read_text())['groups'] if r['id'] == row['id'])
        if obs.get('acquisition_id', obs.get('source_paper_acquisition_id')) != case['source_parent_id'] or obs['grade'] != row['shape']['grade'] or obs['material_and_question_PDF_pages'] != case['PDF_pages']:
            raise ValueError('Profile catalogue parent/grade/page scope differs')
        record = json.loads(load_ref(case['transcription']).read_text())['records'][case['record_index']]
        if (record['id'] != row['id'] or record['grade'] != row['shape']['grade'] or record['family'] != row['shape']['family'] or
                record['candidate_input'] != row['shape']['details']['input'] or record['question_numbers'] != obs['question_numbers'] or len(record['question_numbers']) != row['shape']['responses']):
            raise ValueError('Profile response/card/input configuration differs')
        if record['source_images'] != case['source_images'] or len(case['source_images']) != len(case['PDF_pages']):
            raise ValueError('Required original page images omitted/reordered')
        for image in case['source_images']:
            if sum(r.get('path') == image['path'] and r.get('sha256') == image['sha256'] for r in acquisitions.values()) != 1:
                raise ValueError('Required original image is not registered')
            load_ref(image)
        if not record['all_relevant_pages_actually_visually_read'] or not record['author_prepared_bundle_complete'] or record['independent_transcription'] or record['independent_gold']:
            raise ValueError('Author-only visual bundle scope differs')
        if (not record['one_extra_explicit'] or '多余选项' not in record['components'][0]['text'] or
                record['max_use_per_candidate_explicit'] is not None):
            raise ValueError('Spare option does not establish an explicit once-only rule')
        cs = record['components'];by_id = {c['id']: c for c in cs}
        if len(by_id) != len(cs) or {c['id']: digest(c['text']) for c in cs} != case['component_hashes']:
            raise ValueError('Source components changed, duplicated or omitted')
        counts = {}
        for c in cs:
            if c['role'] not in ['instruction', 'material_label', 'candidate_text', 'candidate_schedule', 'profile_name', 'profile_text'] or any(x in c['text'] for x in ['【答案】', '【解析】']):
                raise ValueError('Private answer or author description is not student input')
            role = counts.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(c['text']).items():
                role[k] += v
            role['components'] += 1
        cards = record['candidate_cards']
        if len(cards) != row['shape']['details']['cards'] or [c['label'] for c in cards] != list('ABCD'):
            raise ValueError('Shared four-card set incomplete')
        parts = [];used = []
        for card in cards:
            if record['candidate_input'] == 'images':
                expected_grid = case['source_images'][1] if row['id'] == 'g8.fengtai2026.imageMatching' else case['source_images'][0]
                if card['required_image'] != expected_grid or card['grid_position'] != dict(zip('ABCD', ['top_left', 'top_right', 'bottom_left', 'bottom_right']))[card['label']]:
                    raise ValueError('Image candidate grid association differs')
                if not record['image_card_labels_not_replaced_with_author_device_or_activity_names'] or record['image_glyph_text_counts_complete']:
                    raise ValueError('Required images cannot be replaced by author labels or full text-load claims')
            else:
                members = [by_id[cid] for cid in card['component_ids']]
                if sum(c['role'] == 'candidate_text' for c in members) != 1 or any(c.get('candidate_label') != card['label'] for c in members):
                    raise ValueError('Candidate material/title/schedule belongs to another card')
                used += card['component_ids']
                text = '\n'.join(c['text'] for c in members);parts.append(text)
                atomic[row['id'] + '.card' + card['label']] = normalized(text)
        if set(used) != {c['id'] for c in cs if 'candidate_label' in c} or len(used) != len(set(used)):
            raise ValueError('Text candidates omitted or reused as independent material')
        profiles = [c for c in cs if c['role'] == 'profile_text']
        names = [c for c in cs if c['role'] == 'profile_name']
        if [c['item_id'] for c in profiles] != obs['question_numbers'] or [c['item_id'] for c in names] != obs['question_numbers']:
            raise ValueError('Profile name/response allocation differs')
        for c in profiles:
            parts.append(c['text']);atomic[row['id'] + '.' + c['id']] = normalized(c['text'])
        gid = row['id'];norm = normalized('\n'.join(parts))
        if gid in bodies:
            raise ValueError('Repeated source profile group')
        bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'grade': row['shape']['grade'],
                        'normalized_material_sha256': digest(norm), 'component_counts': counts,
                        'candidate_input': record['candidate_input'], 'text_candidate_cards': 4 if record['candidate_input'] == 'text_cards' else 0,
                        'required_image_candidate_cards': 4 if record['candidate_input'] == 'images' else 0,
                        'responses': len(profiles), 'max_use_per_candidate_explicit': None,
                        'comparison_scope': 'text cards+schedule+profiles; image task profiles only, original images bound but visual content not family-screened',
                        'frozen_source_input_state': row['necessary_input_complete'], 'author_prepared_bundle_complete': True,
                        'independent_transcription': False, 'independent_gold': False})
        layouts[gid] = {'source_shape': row['shape'], 'parent_document': case['parent_document'], 'transcription': case['transcription'],
                        'required_source_images': case['source_images'], 'candidate_cards': cards,
                        'profiles': [{'item_id': c['item_id'], 'id': c['id'], 'sha256': digest(c['text'])} for c in profiles],
                        'component_hashes': case['component_hashes'], 'one_extra_explicit': True, 'max_use_per_candidate_explicit': None,
                        'author_prepared_bundle_complete': True, 'independent_transcription': False,
                        'frozen_source_input_state': row['necessary_input_complete']}
    return records, bodies, atomic, layouts


def prior_materials(manifest):
    bank_manifest = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    old, records, _ = ancestor_materials(bank_manifest)
    new_records, new, _, _ = bank_views(bank_manifest)
    if set(old) & set(new):
        raise ValueError('Repeated ancestor source')
    old.update(new);records += new_records
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Ancestor text normalization changed')
    return old, records, prior


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid]:
        raise ValueError('Profile candidate/input/name/response/reuse binding differs')
    if any(request.get(k) for k in ['use_as_verified_answer_gold', 'claim_production_supported', 'claim_independent_review', 'claim_visual_deduplication_complete']):
        raise ValueError('Author visual bundle is not independent gold, production or visual-family validation')
    return {'source_profile_layout_matches': True, 'evidence_group_id': gid, 'author_prepared_bundle_complete': True,
            'frozen_source_input_state': layouts[gid]['frozen_source_input_state'], 'model_called': False,
            'independent_gold': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text());records, new, atomic, _ = profile_views(manifest);old, old_records, prior = prior_materials(manifest)
    if set(old) & set(new):
        raise ValueError('Source matching group already screened')
    comparisons = [{'left': left, 'right': right, **compare(a, b)} for left, a in new.items() for right, b in old.items()]
    comparisons += [{'left': left, 'right': right, **compare(new[left], new[right])} for left, right in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Group comparison coverage differs')
    atomic_candidates = [];atomic_pairs = 0
    for left, a in atomic.items():
        for right, b in old.items():
            result = compare(a, b);atomic_pairs += 1
            if result['review_candidate']:
                atomic_candidates.append({'left': left, 'right': right, **result})
    for left, right in combinations(atomic, 2):
        result = compare(atomic[left], atomic[right]);atomic_pairs += 1
        if result['review_candidate']:
            atomic_candidates.append({'left': left, 'right': right, **result})
    return {'version': '0.1', 'records_scope': 'five new source matching views; old217 via frozen refs',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons), 'comparisons': comparisons,
            'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'atomic_text_units': len(atomic), 'atomic_pairs_checked_separate_not_added_to_group_pairs': atomic_pairs, 'atomic_candidates': atomic_candidates,
            'catalogue_response_positions': 15, 'text_candidate_cards': 12, 'required_image_candidate_cards': 8,
            'all_benchmark_deduplication_complete': False, 'visual_image_content_family_screened': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path);parser.add_argument('--request', type=Path);args = parser.parse_args()
    if args.request:
        _, _, _, layouts = profile_views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived data must stay in ignored build/')
        result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Refuse a changed report overwrite')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'review_candidates', 'atomic_text_units', 'atomic_pairs_checked_separate_not_added_to_group_pairs']}))
    else:
        parser.error('Choose --request or --output')
