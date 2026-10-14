#!/usr/bin/env python3
"""Bind open response operations, source score declarations and given-word policies."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_school_material_families import digest
from audit_cloze_materials import normalized
from audit_baseline_bank_forms import compare
from audit_baseline_text_spans import ancestors, span_views
from audit_jiexiu_selected_modes import views as jiexiu_views
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-open-form-views-v0.1.json'


def open_form_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    records, bodies, layouts = [], {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']];parent = acquisitions[case['source_parent_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id'] or case['parent_document'] != {'path': parent['path'], 'sha256': parent['sha256']}:
            raise ValueError('Open/form source layer/parent/version differs')
        load_ref(case['parent_document'])
        obs = next(r for r in json.loads(load_ref(case['source_catalogue']).read_text())['groups'] if r['id'] == row['id'])
        if obs['source_paper_acquisition_id'] != row['paper_id'] or obs['grade'] != row['shape']['grade'] or obs['material_and_question_PDF_pages'] != case['PDF_pages']:
            raise ValueError('Open/form catalogue identity/page allocation differs')
        record = json.loads(load_ref(case['transcription']).read_text())['records'][case['record_index']]
        if record['id'] != row['id'] or record['family'] != row['shape']['family'] or record['grade'] != row['shape']['grade'] or record['printed_numbers'] != obs['question_numbers'] or record['responses'] != row['shape']['responses']:
            raise ValueError('Open/form record/mode/response sequence differs')
        if record['source_images'] != case['source_images'] or record['PDF_pages'] != case['PDF_pages'] or len(case['source_images']) != len(case['PDF_pages']):
            raise ValueError('Required source page omitted/reordered')
        for image in case['source_images']:
            if sum(a.get('path') == image['path'] and a.get('sha256') == image['sha256'] for a in acquisitions.values()) != 1:
                raise ValueError('Required original PNG not registered')
            load_ref(image)
        cs = record['components'];by_id = {c['id']: c for c in cs};counts = {};parts = []
        if len(by_id) != len(cs) or {c['id']: digest(c['text']) for c in cs} != case['component_hashes']:
            raise ValueError('Missing/changed/duplicate source component')
        for c in cs:
            if c['role'] not in ['instruction', 'scoring_declaration', 'optional_declaration', 'material_label', 'passage', 'prompt', 'given_hint'] or any(s in c['text'] for s in ['【答案】', '【解析】']):
                raise ValueError('Private reference/author rationale is not student input')
            text = c['text']
            if c['role'] == 'passage':
                parts.append(text)
                text = re.sub(r'_+\d+_+\s*\([^()]+\)', ' ', text)
                text = re.sub(r'_+\d+_+', ' ', text)
            role = counts.setdefault(c['role'], {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0})
            for k, v in count(text).items():
                role[k] += v
            role['components'] += 1
        if not parts or len([c for c in cs if c['role'] == 'instruction']) != 1 or len([c for c in cs if c['role'] == 'scoring_declaration']) != 1:
            raise ValueError('Material/instruction/scoring source component omitted')
        raw_body = '\n'.join(parts);details = row['shape']['details'];body = raw_body
        if record['family'] == 'open_reading_response':
            prompts = [c for c in cs if c['role'] == 'prompt']
            if [c['item_id'] for c in prompts] != record['printed_numbers'] or 'given_hint' in counts:
                raise ValueError('Open response prompts missing/reassigned')
            points = details['points'];expected_points = points if isinstance(points, list) else [points] * len(prompts)
            if record['points_each'] != expected_points or record['analytic_point_split_established'] or record['per_response_word_limit_explicit'] is not None or record['last_prompt_word_target'] is not None:
                raise ValueError('Printed whole-question scores do not establish analytic splits or word limits')
            requirement = record['last_response_requirement'];last = prompts[-1]['text']
            if requirement['operation'] != details['last_operation'] or requirement['independent_response_fields'] != 1:
                raise ValueError('Whole final response operation differs')
            if details['last_operation'] == 'opinion_plus_two_reasons':
                if 'Please give two reasons.' not in last or requirement['explicit_reasons'] != 2 or not requirement['reason_required']:
                    raise ValueError('Explicit two reasons omitted')
            else:
                if requirement['explicit_reasons'] is not None or requirement['reason_required'] != ('Why?' in last):
                    raise ValueError('Reason count invented or printed reason request omitted')
            extra = {'last_response_requirement': requirement, 'analytic_point_split_established': False,
                     'per_response_word_limit_explicit': None, 'points_each': record['points_each']}
        else:
            slots = record['slots'];hint_components = [c for c in cs if c['role'] == 'given_hint']
            blanks = [int(n) for n in re.findall(r'_+(\d+)_+', raw_body)]
            if blanks != record['printed_numbers'] or [s['printed_number'] for s in slots] != blanks or 'prompt' in counts:
                raise ValueError('Whole grammar blank sequence differs')
            all_given = obs['features'].get('given_words_each') or obs['features'].get('all_blanks_given_word')
            expected_given = obs['features'].get('given_word_numbers', blanks if all_given else None)
            if [c['item_id'] for c in hint_components] != expected_given:
                raise ValueError('Given/ungiven source pattern differs')
            for slot in slots:
                n = slot['printed_number'];a, b = slot['body_blank_offsets']
                if raw_body[a:b] != '__' + str(n) + '__':
                    raise ValueError('Grammar response assigned to another blank')
                hint = slot['given_hint_component']
                if slot['word_limit'] != (None if hint else 1):
                    raise ValueError('Given-word forms cannot be forced to one word')
                if hint:
                    c = by_id[hint]
                    if c['role'] != 'given_hint' or c['item_id'] != n or not raw_body[b:].lstrip().startswith('(' + c['text'] + ')'):
                        raise ValueError('Given word belongs to another gap')
            source_optional = obs.get('optional_source_layer', obs['features'].get('optional_score_component', False))
            if record['source_optional'] != source_optional:
                raise ValueError('Source optional grammar became compulsory')
            if record['source_optional']:
                if record['points_total'] != 4 or record['points_each'] is not None or record['equal_points_per_blank_explicit'] or 'optional_declaration' not in counts:
                    raise ValueError('Total4 is not an explicit per-blank score statement')
            elif record['points_each'] != [1] * 10:
                raise ValueError('Printed per-item grammar points differ')
            body = re.sub(r'_+\d+_+\s*\([^()]+\)', ' ', raw_body);body = re.sub(r'_+\d+_+', ' ', body)
            extra = {'slots': slots, 'source_optional': record['source_optional'], 'points_each': record['points_each'],
                     'points_total': record.get('points_total'), 'equal_points_per_blank_explicit': record.get('equal_points_per_blank_explicit')}
        gid = row['id'];norm = normalized(body)
        if gid in bodies:
            raise ValueError('Repeated source transcription')
        bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'grade': row['shape']['grade'],
                        'normalized_material_sha256': digest(norm), 'component_counts': counts, 'responses': record['responses'],
                        'mode_specific_observations': extra, 'frozen_source_input_state': row['necessary_input_complete'],
                        'transcription_independent': False, 'source_input_quality_or_gold_not_upgraded': True})
        layouts[gid] = {'source_shape': row['shape'], 'parent_document': case['parent_document'], 'transcription': case['transcription'],
                        'component_hashes': case['component_hashes'], 'required_source_images': case['source_images'],
                        'printed_numbers': record['printed_numbers'], **extra, 'frozen_source_input_state': row['necessary_input_complete']}
    return records, bodies, layouts


def prior_views(manifest):
    previous = json.loads(load_ref(manifest['prior_view_manifest']).read_text());native = json.loads(load_ref(previous['prior_view_manifest']).read_text())
    old, records, _ = ancestors(native);new_records, new, _ = span_views(native)
    if set(old) & set(new):
        raise ValueError('Repeated ancestor native source')
    old.update(new);records += new_records;new_records, new, _ = jiexiu_views(previous)
    if set(old) & set(new):
        raise ValueError('Repeated ancestor selected source')
    old.update(new);records += new_records;prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Prior text normalization changed')
    return old, records, prior


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid]:
        raise ValueError('Open operation/reason/score/word/optional/hint/input binding differs')
    if any(request.get(k) for k in ['claim_independent_transcription', 'use_as_verified_answer_gold', 'claim_production_supported', 'claim_factual_review_complete']):
        raise ValueError('Author transcription/structure is not independent, semantic gold, production or fact verification')
    return {'source_open_form_layout_matches': True, 'evidence_group_id': gid, 'frozen_source_input_state': layouts[gid]['frozen_source_input_state'],
            'model_called': False, 'independent_gold': False, 'production_supported': False}


def audit():
    manifest = json.loads(MANIFEST.read_text());records, new, _ = open_form_views(manifest);old, old_records, prior = prior_views(manifest)
    if set(old) & set(new):
        raise ValueError('Source view already screened')
    comparisons = [{'left': left, 'right': right, **compare(a, b)} for left, a in new.items() for right, b in old.items()]
    comparisons += [{'left': left, 'right': right, **compare(new[left], new[right])} for left, right in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Source comparison coverage differs')
    return {'version': '0.1', 'records_scope': 'five new baseline views; prior233 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records, 'comparisons': comparisons,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'response_positions_this_batch': 27, 'all_benchmark_deduplication_complete': False,
            'zero_candidates_not_independent_families': True, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path);parser.add_argument('--request', type=Path);args = parser.parse_args()
    if args.request:
        _, _, layouts = open_form_views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived data must stay in ignored build/')
        result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Refuse changed report overwrite')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'response_positions_this_batch', 'review_candidates']}))
    else:
        parser.error('Choose --request or --output')
