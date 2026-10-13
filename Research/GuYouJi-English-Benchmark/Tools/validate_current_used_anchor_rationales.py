#!/usr/bin/env python3
"""Check reasons against actual current authoring anchors; partial coverage is explicit."""
import argparse
import json
import validate_firstrelease_v0_3 as core
import validate_seed_answer_values_v0_1 as values


def check(index, require_complete=False):
    errors = []
    review_path = core.BASE / index['current_review_index_path']
    if core.digest(review_path) != index['current_review_index_sha256']:
        errors.append('current review binding differs')
    review = json.loads(review_path.read_text())
    required = {g for row in review['candidates'] for g in row['anchor_group_ids']}
    observations = {g['id']: g for g in json.loads((core.BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}
    acquisitions = {a['id']: a for a in json.loads((core.BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    record = acquisitions[index['private_rationale_acquisition_id']]
    path = core.REPO / record['path']
    if core.digest(path) != index['private_rationale_sha256'] or record['sha256'] != index['private_rationale_sha256']:
        errors.append('private rationale binding differs')
    private = json.loads(path.read_text())
    included = {g['group_id'] for g in private['groups']}
    if len(included) != len(private['groups']) or included - required:
        errors.append('duplicate or unused source group included')
    count = sum(len(g['items']) for g in private['groups'])
    required_count = sum(len(observations[g]['question_numbers']) for g in required)
    missing = sorted(required - included)
    if index['missing_group_ids'] != missing or private['missing_group_ids'] != missing:
        errors.append('missing source list differs from current actual usage')
    if index['group_count'] != len(included) or index['item_count'] != count or index['required_group_count'] != len(required) or index['required_item_count'] != required_count:
        errors.append('declared included/required counts differ')
    if len(index['groups']) != len(private['groups']):
        errors.append('public/private group counts differ')
    else:
        for public, detail in zip(index['groups'], private['groups']):
            if public['group_id'] != detail['group_id'] or public['question_numbers'] != [i['source_number'] for i in detail['items']]:
                errors.append('public/private source item pairing differs')
            if any(not i['author_analysis'].strip() for i in detail['items']):
                errors.append('missing source item reason')
            excluded = [i['source_number'] for i in detail['items'] if not i['positive_answer_example']]
            if public['positive_answer_examples_excluded_source_numbers'] != excluded:
                errors.append('source exclusion not preserved')
    answer_values = values.check(private, observations, acquisitions)
    errors += answer_values['errors']
    for field in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission']:
        if index[field] is not False:
            errors.append('unsupported external admission: ' + field)
    if require_complete and missing:
        errors.append('required current-used rationale coverage incomplete')
    return {'bindings_and_structure_valid': not errors, 'errors': errors,
            'source_groups_with_rationales': len(included), 'source_items_with_rationales': count,
            'required_source_groups': len(required), 'required_source_items': required_count,
            'missing_group_ids': missing, 'required_rationale_coverage_complete': not missing,
            'answer_value_validation': answer_values,
            'independent_semantic_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', default=str(core.BASE / 'FirstRelease/current-used-anchor-rationale-index-v0.1.json'))
    parser.add_argument('--require-complete', action='store_true')
    args = parser.parse_args()
    result = check(json.loads(open(args.index).read()), args.require_complete)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['bindings_and_structure_valid'] else 1)
