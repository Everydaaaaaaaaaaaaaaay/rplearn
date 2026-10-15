#!/usr/bin/env python3
"""Keep known shared-narrative exposure out of opposing research partitions.

Only checks registered constraints; passing never certifies full independence.
No split is changed and no model, hidden evaluation or student trial is run.
"""
import argparse
import json
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest

FAMILIES = BASE / 'FirstRelease/Sampling/material-exposure-families-v0.1.json'


def check(request):
    ref = {'path': str(FAMILIES.relative_to(BASE)), 'sha256': digest(FAMILIES.read_text())}
    if request.get('family_definition') != ref:
        raise ValueError('Known family-definition version differs')
    data = json.loads(load_ref(ref).read_text())
    load_ref(data['nomination_report'])
    load_ref(data['author_review'])
    source_ids = {row['id'] for row in evidence()}
    assignment = {}
    for row in request.get('assignments', []):
        gid, partition = row['group_id'], row['partition']
        if gid not in source_ids or gid in assignment or partition not in ['train', 'development', 'heldout', 'unused']:
            raise ValueError('Unknown/repeated source or invalid research partition')
        assignment[gid] = partition
    if not assignment:
        raise ValueError('At least one explicit source assignment is required')
    for family in data['exposure_families']:
        used = {assignment[gid] for gid in family['source_group_ids'] if gid in assignment and assignment[gid] != 'unused'}
        if len(used) > 1:
            raise ValueError('Known narrative-exposure family crosses research partitions: ' + family['id'])
    if any(request.get(key) for key in ['claim_all_materials_independent', 'claim_semantic_review_complete',
                                        'claim_original_source_reuse_proven', 'transfer_answers_across_family',
                                        'claim_student_calibrated', 'claim_commercial_admission', 'claim_production_supported']):
        raise ValueError('Known-family checks cannot certify unknown families, answer transfer or validation')
    return {'known_family_constraints_passed': True, 'assigned_source_records': len(assignment),
            'registered_exposure_families': len(data['exposure_families']),
            'full_semantic_visual_independence_verified': False, 'answer_transfer_permitted': False,
            'actual_split_mutated': False, 'model_or_production_called': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(json.loads(args.request.read_text()))))
