#!/usr/bin/env python3
"""Current core plus exact-used complete source reasons and risk exclusions."""
import json
import validate_firstrelease_v0_9 as previous
import validate_current_used_anchor_rationales as used

core = previous.current.core


def check(data, check_cache=False):
    result = previous.check(data, check_cache)
    try:
        index = json.loads(core.file_ref(data['current_used_anchor_rationale_index']).read_text())
        bound_review = json.loads((core.BASE / index['current_review_index_path']).read_text())
        if data['candidates'] != bound_review['candidates'] or data['selected_source_groups'] != bound_review['selected_source_groups']:
            raise ValueError('rationale usage binding does not match actual current selections')
        if check_cache:
            report = used.check(index, require_complete=True)
            result['errors'] += report['errors']
            result['actual_used_anchor_rationale_validation'] = report
        else:
            result['actual_used_anchor_rationale_validation'] = {'requires_check_cache': True, 'executed': False}
    except (KeyError, ValueError, OSError) as exc:
        result['errors'].append('actual used source reasons: ' + str(exc))
    result['bindings_and_structure_valid'] = not result['errors']
    return result


if __name__ == '__main__':
    core.author_evidence_count = previous.current.author_evidence_count
    core.DEFAULT = core.BASE / 'FirstRelease/review-index-v0.10.json'
    core.check = check
    raise SystemExit(core.main())
