#!/usr/bin/env python3
"""Keep pure heading selection distinct from sentence insertion and mixed modes."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, REPO, evidence, load_ref, check_request
from audit_school_material_families import digest, remove_offsets
from audit_cloze_materials import normalized
from audit_baseline_bank_forms import compare
from audit_baseline_text_spans import ancestors, span_views
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/jiexiu-heading-sentence-views-v0.1.json'


def views(manifest):
    sources = {r['id']: r for r in evidence()};records = [];bodies = {};layouts = {}
    for case in manifest['views']:
        row = sources[case['group_id']]
        if row['layer'] != 'new_structure_only' or row['paper_id'] != case['source_paper_id'] or row['shape']['grade'] != case['source_grade'] or row['source_text_ref'] != case['source_text']:
            raise ValueError('Selected source layer/parent/grade/text differs')
        text = load_ref(case['source_text']).read_text();raw = text[case['material_start']:case['material_end']]
        if digest(raw) != case['material_sha256']:
            raise ValueError('Selected material boundary differs')
        body = remove_offsets(raw, case['excluded_offsets'], ' ');blanks = [r['blank_id'] for r in case['excluded_offsets'] if r['role'] == 'blank_label']
        if blanks != case['printed_numbers'] or len(blanks) != row['shape']['responses'] or case['slot_roles'] != row['shape']['details']['slot_roles']:
            raise ValueError('Response count/number/heading-sentence role differs')
        heading = row['shape']['family'] == 'paragraph_heading_matching'
        if (heading and (case['slot_roles'] != ['heading'] * 5 or blanks != list(range(34, 39)))) or (not heading and (case['slot_roles'] != ['sentence'] * 5 or blanks != list(range(49, 54)))):
            raise ValueError('Pure headings and paragraph sentence gaps cannot be merged')
        candidates = case['shared_candidates']
        expected = row['shape']['details']['shared_options']
        if len(candidates) != expected or [c['label'] for c in candidates] != list('ABCDEF'[:expected]):
            raise ValueError('Actual shared candidate count differs')
        candidate_texts = []
        for c in candidates:
            value = text[c['start']:c['end']]
            if not 0 <= c['start'] < c['end'] <= len(text) or digest(value) != c['sha256'] or not value.strip():
                raise ValueError('Shared candidate text boundary differs')
            candidate_texts.append(value)
        instruction = case['instruction'];value = text[instruction['start']:instruction['end']]
        if digest(value) != instruction['sha256'] or ('小标题' in value) != heading:
            raise ValueError('Heading/sentence instruction differs')
        if heading:
            if row['shape']['details']['explicit_spare'] is not None or expected - len(blanks) != 0 or row['shape']['details']['observed_candidates_minus_responses'] != 0:
                raise ValueError('Five titles/five slots do not establish an explicit reuse rule')
        elif '一项为多余项' not in value or expected - len(blanks) != 1 or row['shape']['details']['explicit_spare'] != 1:
            raise ValueError('Sentence spare/count policy differs')
        if row['shape']['details']['reuse_rule'] != 'not_explicit':
            raise ValueError('Source does not print a once-only rule')
        gid = row['id'];norm = normalized(body)
        if gid in bodies:
            raise ValueError('Repeated group')
        bodies[gid] = norm
        records.append({'group_id': gid, 'paper_identity': row['paper_id'], 'grade': 7, 'family': row['shape']['family'],
                        'normalized_material_sha256': digest(norm), 'material_counts_without_blank_labels_or_footer': count(body),
                        'candidate_counts_without_labels': count('\n'.join(candidate_texts)), 'responses': len(blanks),
                        'shared_options': expected, 'slot_roles': case['slot_roles'], 'reuse_rule': 'not_explicit',
                        'necessary_student_input_complete': row['necessary_input_complete'], 'source_key_is_not_independent_gold': True,
                        'source_broken_closing_line_not_corrected': heading})
        layouts[gid] = {'shape': row['shape'], 'source_text': case['source_text'], 'material_sha256': case['material_sha256'],
                        'printed_numbers': blanks, 'slot_roles': case['slot_roles'], 'shared_candidates': candidates,
                        'instruction': instruction, 'reuse_rule': 'not_explicit'}
    return records, bodies, layouts


def check(request, layouts):
    gid = request.get('evidence_group_id')
    if gid not in layouts or request.get('layout') != layouts[gid]:
        raise ValueError('Heading/sentence/count/candidate/source layout differs')
    if request.get('claim_suzhou_mixed_mode_replication') or request.get('claim_exclusive_grade'):
        raise ValueError('Different complete modes do not establish mixed-mode replication or grade exclusivity')
    return check_request({'evidence_group_id': gid, 'grade': layouts[gid]['shape']['grade'], 'shape': layouts[gid]['shape'],
                          'requires_complete_student_input': True, 'use_as_verified_answer_gold': request.get('use_as_verified_answer_gold', False),
                          'claim_production_supported': request.get('claim_production_supported', False)}, evidence())


def audit():
    manifest = json.loads(MANIFEST.read_text());records, new, _ = views(manifest)
    old_manifest = json.loads(load_ref(manifest['prior_view_manifest']).read_text());old, old_records, _ = ancestors(old_manifest)
    previous_records, previous, _ = span_views(old_manifest)
    if set(old) & set(previous):
        raise ValueError('Repeated prior source')
    old.update(previous);old_records += previous_records;prior = json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old) != prior['material_count_total'] or any(digest(old[r['group_id']]) != r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Previous text views changed')
    if set(old) & set(new):
        raise ValueError('Selected source already screened')
    comparisons = [{'left': left, 'right': right, **compare(a, b)} for left, a in new.items() for right, b in old.items()]
    comparisons += [{'left': left, 'right': right, **compare(new[left], new[right])} for left, right in combinations(new, 2)]
    total = len(old) + len(new);pairs = total * (total - 1) // 2
    if pairs != prior['pair_count_total'] + len(comparisons):
        raise ValueError('Source text comparison coverage differs')
    return {'version': '0.1', 'records_scope': 'two new selected text modes; prior231 via frozen references',
            'prior_records_and_comparisons': manifest['prior_material_audit'], 'records': records, 'comparisons': comparisons,
            'material_count_total': total, 'parent_count_total': len({r['paper_identity'] for r in old_records + records}),
            'pair_count_total': pairs, 'prior_pairs_reused': prior['pair_count_total'], 'new_pair_count': len(comparisons),
            'exact_repeat_pairs': prior['exact_repeat_pairs'] + sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates': prior['review_candidates'] + sum(c['review_candidate'] for c in comparisons),
            'all_benchmark_deduplication_complete': False, 'mixed_heading_sentence_second_region_established': False,
            'zero_candidates_not_independent_families': True, 'model_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__);parser.add_argument('--output', type=Path);parser.add_argument('--request', type=Path);args = parser.parse_args()
    if args.request:
        _, _, layouts = views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()), layouts)))
    elif args.output:
        if (REPO / 'build').resolve() not in args.output.resolve().parents:
            parser.error('Source-derived profiles stay in ignored build/')
        result = audit();payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
        if args.output.exists() and args.output.read_text() != payload:
            raise ValueError('Refuse changed report overwrite')
        if not args.output.exists():
            args.output.write_text(payload)
        print(json.dumps({k: result[k] for k in ['material_count_total', 'parent_count_total', 'pair_count_total', 'new_pair_count', 'review_candidates']}))
    else:
        parser.error('Choose --request or --output')
