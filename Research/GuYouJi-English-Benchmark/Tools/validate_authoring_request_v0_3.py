#!/usr/bin/env python3
"""Validate local dual-input requests against current used or corrected seed sources."""
import argparse
import json
from pathlib import Path
import validate_firstrelease_v0_3 as core


def check(request, review):
    errors = []
    role = None
    try:
        source = {g['id']: g for g in json.loads((core.BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}[request['anchor_group_id']]
        if not source['complete_selected_group_reviewed']:
            raise ValueError('complete matching source group not available')
        current_spec = next(g for g in review['grades'] if g['grade'] == request['grade'])['current_specification']
        core.file_ref(request['specification'])
        if request['specification'] != current_spec or source['grade'] != request['grade']:
            raise ValueError('wrong grade/current specification')
        if request['source_paper_acquisition_id'] != source['acquisition_id'] or request['source_observation_sha256'] != core.canonical(source):
            raise ValueError('wrong paper or source observation version')
        frozen = next(g for g in review['selected_source_groups'] if g['id'] == source['id'])
        if frozen['canonical_sha256'] != core.canonical(source):
            raise ValueError('source observation differs from frozen review catalog')
        parent = next(a for a in json.loads((core.BASE / 'Registry/acquisitions.json').read_text())['acquisitions']
                      if a['id'] == source['acquisition_id'])
        parent_path = Path(parent['path'])
        if parent_path.is_absolute() or '..' in parent_path.parts or parent_path.parts[0] != 'build':
            raise ValueError('source parent path is not a portable cache reference')
        actual_parent = core.REPO / parent_path
        if actual_parent.stat().st_size != parent['bytes'] or core.digest(actual_parent) != parent['sha256']:
            raise ValueError('source parent file version differs from registered bytes')
        candidates = [('actual_used', review['current_used_anchor_rationale_index']),
                      ('corrected_seed_control', review['seed_anchor_index'])]
        allowed = {core.canonical(ref): (name, ref) for name, ref in candidates}
        role, ref = allowed[core.canonical(request['rationale_reference'])]
        rationale = json.loads(core.file_ref(ref).read_text())
        row = next(g for g in rationale['groups'] if g['group_id'] == source['id'])
        if request['core_kind'] != row['core_kind']:
            raise ValueError('requested task kind differs from full reference')
        expected = {'items': len(source['question_numbers']),
                    'options_each': source.get('features', {}).get('options_each'),
                    'source_features': source['features']}
        if request['format'] != expected:
            raise ValueError('declared source mode/blank limits/material allocation differs')
        if request['all_shared_material_required'] is not True:
            raise ValueError('complete shared material requirement missing')
        positive = request['positive_source_answer_example_numbers']
        if not isinstance(positive, list) or len(set(positive)) != len(positive) or not set(positive).issubset(source['question_numbers']):
            raise ValueError('invalid positive example source numbers')
        if set(positive) & set(row['positive_answer_examples_excluded_source_numbers']):
            raise ValueError('quarantined source response promoted as positive example')
        if request['source_reference_response_list_exhaustive'] is not False:
            raise ValueError('published reference promoted to exhaustive answer list')
        if not request['scenario'].strip() or not request['target_operations']:
            raise ValueError('new scenario and intended operations required')
        required_outputs = {
            'complete_student_material', 'per_item_evidence_and_all_alternatives',
            'whole_group_refill_or_solve', 'actual_revision_saved_prior_current_if_changed',
            'source_form_kept_and_target_changes_justified',
            'independent_review_and_unknowns_separate',
        }
        declared_outputs = request.get('author_output_required')
        if not isinstance(declared_outputs, list) or not all(isinstance(v, str) for v in declared_outputs) or not required_outputs.issubset(declared_outputs):
            raise ValueError('complete author evidence and revision output requirements missing')
        if any(key in request for key in ['source_full_text', 'source_text_payload']):
            raise ValueError('metadata request must not embed original source full text')
        for field in ['source_text_copy_or_republication_admitted', 'commercial_model_training_admitted',
                      'third_party_source_text_transmission_admitted', 'independent_review',
                      'student_calibration', 'production_admission']:
            if request.get(field) is not False:
                raise ValueError('unsupported admission: ' + field)
        display = request['student_display']
        if display['avatar_next_to_instruction_only'] is not True or display['independent_character_opening_story'] is not False or display['leak_correct_title'] is not False:
            raise ValueError('student display contradicts agreed task scope')
    except (KeyError, ValueError, OSError, IndexError, StopIteration, TypeError) as exc:
        errors.append(str(exc) or type(exc).__name__)
    return {'request_bindings_valid': not errors, 'errors': errors, 'rationale_catalog_role': role,
            'model_called': False, 'original_source_text_transmitted': False,
            'independent_semantic_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', required=True)
    matrix = json.loads((core.BASE / 'FirstRelease/source-matrix.json').read_text())
    parser.add_argument('--index', default=str(core.BASE / matrix['latest_author_review_index_path']))
    args = parser.parse_args()
    result = check(json.loads(open(args.request).read()), json.loads(open(args.index).read()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['request_bindings_valid'] else 1)
