#!/usr/bin/env python3
"""Current v0.7 checks plus seed answer-value validation when cache is checked."""
import json
import validate_firstrelease_v0_7 as current
import validate_seed_answer_values_v0_1 as values


def check(data, check_cache=False):
    result = current.check(data, check_cache)
    if check_cache:
        try:
            seed = json.loads(current.core.file_ref(data['seed_anchor_index']).read_text())
            registry = json.loads((current.core.BASE / 'Registry/acquisitions.json').read_text())
            acquisitions = {r['id']: r for r in registry['acquisitions']}
            record = acquisitions[seed['private_rationale_acquisition_id']]
            private = json.loads((current.core.REPO / record['path']).read_text())
            observations = {r['id']: r for r in json.loads((current.core.BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}
            report = values.check(private, observations, acquisitions)
            result['errors'] += report['errors']
            result['seed_answer_value_validation'] = report
        except (KeyError, ValueError, OSError) as exc:
            result['errors'].append('seed answer values: ' + str(exc))
    else:
        result['seed_answer_value_validation'] = {'requires_check_cache': True, 'executed': False}
    result['bindings_and_structure_valid'] = not result['errors']
    return result


if __name__ == '__main__':
    current.core.author_evidence_count = current.author_evidence_count
    current.core.DEFAULT = current.core.BASE / 'FirstRelease/review-index-v0.9.json'
    current.core.check = check
    raise SystemExit(current.core.main())
