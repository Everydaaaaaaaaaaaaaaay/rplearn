#!/usr/bin/env python3
"""Source-page-bound student transcriptions, separately from frozen empty native text."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest
from audit_baseline_native_materials import native_views
from audit_baseline_prepared_materials import prior_bodies, prepared_views
from audit_cloze_materials import normalized, shingles
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/image-transcribed-material-views-v0.1.json'


def transcribed_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    records, bodies, layouts = [], {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id']:
            raise ValueError('Transcription belongs to another source layer/parent')
        parent = acquisitions[case['source_parent_id']]
        if case['parent_document'] != {'path': parent['path'], 'sha256': parent['sha256']}:
            raise ValueError('Transcription cites another parent version')
        load_ref(case['parent_document'])
        catalogue = json.loads(load_ref(case['source_catalogue']).read_text())
        obs = next(r for r in catalogue['groups'] if r['id'] == case['group_id'])
        if obs.get('acquisition_id', obs.get('source_paper_acquisition_id')) != case['source_parent_id'] or obs['material_and_question_PDF_pages'] != case['PDF_pages']:
            raise ValueError('Original page scope differs')
        data = json.loads(load_ref(case['transcription']).read_text())
        record = data['records'][case['record_index']]
        if record['id'] != row['id'] or record['grade'] != row['shape']['grade'] or record['family'] != row['shape']['family']:
            raise ValueError('Student source record/grade/mode differs')
        if record['item_ids'] != obs['question_numbers'] or record['options_each'] != row['shape']['options_each']:
            raise ValueError('Source response/option configuration differs')
        if record['images'] != case['source_images'] or not record['all_body_questions_options_actually_visually_read']:
            raise ValueError('Reviewed image binding missing')
        if case['student_text_reviewed_complete'] is not True or case['independent_transcription'] is not False or record['independent_gold']:
            raise ValueError('Review scope or gold status differs')
        if len(case['source_images']) != len(case['PDF_pages']):
            raise ValueError('Original page/image allocation incomplete')
        shared = case.get('shared_context_images', [])
        shared_pages = case.get('shared_context_pages', [])
        if len(shared) != len(shared_pages) or set(shared_pages) & set(case['PDF_pages']):
            raise ValueError('Shared instruction page allocation differs')
        all_images = case['source_images'] + shared
        all_pages = case['PDF_pages'] + shared_pages
        author_bindings = case.get('author_page_bindings')
        if author_bindings is not None:
            expected_bindings = [{'parent_id': case['source_parent_id'], 'PDF_page': page, 'image': image}
                                 for page, image in zip(all_pages, all_images)]
            if author_bindings != expected_bindings or record.get('author_page_bindings') != author_bindings:
                raise ValueError('Explicit author-reviewed parent/page binding differs')
        for page, image in zip(all_pages, all_images):
            matches = [r for r in acquisitions.values() if r.get('path') == image['path'] and r.get('sha256') == image['sha256']]
            if len(matches) != 1:
                raise ValueError('Unregistered source image')
            provenance = matches[0].get('derivation', {})
            if provenance and (provenance.get('acquisition_id') != case['source_parent_id'] or provenance.get('PDF_page') != page):
                raise ValueError('Image belongs to another original source/page')
            if not provenance and author_bindings is None:
                raise ValueError('Missing render provenance or explicit author page binding')
            load_ref(image)
        if [c['pointer'] for c in case['components']] != [['records', case['record_index'], 'components', i, 'text'] for i in range(len(record['components']))]:
            raise ValueError('Student components missing/reordered/foreign')
        totals = {};parts = []
        for binding, c in zip(case['components'], record['components']):
            if any(binding.get(k) != c.get(k) for k in ['id', 'role', 'item_id']) or digest(c['text']) != binding['sha256']:
                raise ValueError('Source component binding differs')
            if c['role'] not in ['passage', 'material_label', 'instruction', 'prompt', 'option', 'scoring_declaration', 'illustrated_gloss_label'] or any(t in c['text'] for t in ['【答案】', '【解析】']):
                raise ValueError('Private key/author reason is not student input')
            text = c['text']
            if c['role'] == 'passage':
                parts.append(text)
                text = re.sub(r'_+\d+_+', ' ', text)
            role = totals.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(text).items():
                role[k] += v
            role['components'] += 1
        body = '\n'.join(parts)
        blanks = [int(n) for n in re.findall(r'_+(\d+)_+', body)]
        if blanks != record['blank_numbers'] or (row['shape']['family'] == 'choice_cloze' and blanks != obs['question_numbers']):
            raise ValueError('Cloze blank sequence incomplete')
        if row['shape']['family'] == 'reading_choice' and totals.get('prompt', {}).get('components') != row['shape']['responses']:
            raise ValueError('Reading prompts incomplete')
        for number in record['item_ids']:
            options = [c for c in record['components'] if c['role'] == 'option' and c['item_id'] == number]
            if [c['option_label'] for c in options] != list('ABCD'[:record['options_each']]) or any(not c['text'] for c in options):
                raise ValueError('Original per-response option set incomplete')
        gid = row['id']
        if gid in bodies:
            raise ValueError('Duplicate transcription is not a new instance')
        norm = normalized(body);bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'transcription': case['transcription'],
                        'material_sha256': digest(body), 'normalized_material_sha256': digest(norm),
                        'component_counts': totals, 'responses': row['shape']['responses'],
                        'source_images': case['source_images'], 'student_text_reviewed_complete': True,
                        'frozen_native_input_state': row['necessary_input_complete'], 'independent_transcription': False,
                        'independent_answer_gold': False, 'commercial_admission': False})
        layouts[gid] = {'source_shape': row['shape'], 'transcription': case['transcription'],
                        'source_images': case['source_images'], 'student_text_reviewed_complete': True,
                        'source_image_scopes': case['source_image_scopes'],
                        'frozen_source_input_state': row['necessary_input_complete'], 'blank_numbers': blanks}
        if author_bindings is not None:
            policy = case.get('source_policy')
            if policy is None or record.get('source_policy') != policy or len(case['source_image_scopes']) != len(all_images):
                raise ValueError('Source score/media/gloss scope omitted or changed')
            layouts[gid].update(source_images=all_images, author_page_bindings=author_bindings, source_policy=policy)
            records[-1].update(source_policy=policy, image_parent_page_binding='author_visual_binding_not_registered_derivation')
    return records, bodies, layouts


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid] or request.get('included_source_images') != layouts[gid]['source_images']:
        raise ValueError('Reviewed text/source-image/shape/blank binding differs')
    if any(request.get(k) for k in ['use_as_verified_answer_gold', 'claim_production_supported', 'claim_factual_review_complete', 'claim_student_calibrated', 'claim_semantic_family_screen_complete']):
        raise ValueError('Visual author transcription is not independent gold or production support')
    return {'reviewed_source_text_preparation_matches': True, 'evidence_group_id': gid,
            'student_text_reviewed_complete': True, 'frozen_source_input_state': layouts[gid]['frozen_source_input_state'],
            'independent_answer_gold': False, 'model_called': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text())
    records, new, _ = transcribed_views(manifest)
    native_manifest = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    nrecords, nbodies, _ = native_views(native_manifest)
    prepared_manifest = json.loads(load_ref(native_manifest['prior_view_manifest']).read_text())
    old, earlier = prior_bodies(prepared_manifest)
    precords, pbodies = prepared_views(prepared_manifest)
    if set(old) & set(pbodies) or set(old) & set(nbodies) or set(pbodies) & set(nbodies):
        raise ValueError('Repeated ancestor identity')
    old.update(pbodies);old.update(nbodies)
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Prior native normalization differs')
    if set(old) & set(new):
        raise ValueError('Original instance already screened')
    bodies = dict(old, **new);comparisons = []
    for left, right in combinations(bodies, 2):
        if left in old and right in old:
            continue
        a, b = shingles(bodies[left]), shingles(bodies[right]);exact = bodies[left] == bodies[right]
        jac = len(a & b) / len(a | b) if a | b else 0;con = len(a & b) / min(len(a), len(b)) if a and b else 0
        comparisons.append({'left': left, 'right': right, 'exact_normalized_match': exact,
                            'fivegram_jaccard': jac, 'fivegram_containment': con,
                            'review_candidate': exact or jac >= .5 or con >= .8})
    total = len(bodies) * (len(bodies) - 1) // 2
    if total != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Cross-layer pair coverage differs')
    return {'version': '0.1', 'records_scope': 'two new image-transcribed source profiles; prior210 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': len(bodies), 'parent_count_total': len({r['paper_identity'] for r in earlier['records'] + precords + nrecords + records}),
            'pair_count_total': total, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'frozen_empty_native_records_unchanged': True, 'all_benchmark_deduplication_complete': False,
            'zero_candidates_not_independent_families': True, 'independent_transcription': False, 'model_called': False}


def continuation_audit(manifest):
    """Reuse the frozen sentence-view ancestors; compare only new image groups."""
    from audit_baseline_sentence_banks import old_views, sentence_views
    from audit_baseline_bank_forms import compare
    previous = json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    old, old_records, _ = old_views(previous)
    recent_records, recent, _, _ = sentence_views(previous)
    if set(old) & set(recent):
        raise ValueError('Duplicate prior source')
    old.update(recent);old_records += recent_records
    prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    # The latest audit records only its delta; ancestors validate their own hashes.
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Frozen previous image audit inputs changed')
    records, new, _ = transcribed_views(manifest)
    if set(old) & set(new):
        raise ValueError('Repeated source is not a new group')
    comparisons = [{'left': l, 'right': r, **compare(a, b)} for l, a in new.items() for r, b in old.items()]
    comparisons += [{'left': l, 'right': r, **compare(new[l], new[r])} for l, r in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Incremental pair coverage differs')
    return {'version': '0.1', 'records_scope': 'new image-transcribed groups; previous247 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'comparisons': comparisons, 'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'frozen_empty_native_records_unchanged': True, 'all_benchmark_deduplication_complete': False,
            'zero_candidates_not_independent_families': True, 'independent_transcription': False, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--request', type=Path)
    parser.add_argument('--continuation-manifest', type=Path)
    args = parser.parse_args()
    if args.request:
        _, _, layouts = transcribed_views(json.loads((args.continuation_manifest or MANIFEST).read_text()))
        print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        from grade_mode_evidence import REPO
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived report must stay in ignored build/')
        result = continuation_audit(json.loads(args.continuation_manifest.read_text())) if args.continuation_manifest else audit()
        payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Do not overwrite a different image-source audit')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'exact_repeat_pairs', 'review_candidates']}))
    else:
        parser.error('Choose --request or --output')
