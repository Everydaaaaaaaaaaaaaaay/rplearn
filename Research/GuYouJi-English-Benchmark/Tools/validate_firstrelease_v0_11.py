#!/usr/bin/env python3
"""Current core and source-usage coverage allow actual candidate text revisions."""
import json
import validate_firstrelease_v0_9 as previous
import validate_current_used_anchor_rationales as used

core = previous.current.core


def check(data, check_cache=False):
    result = previous.check(data, check_cache)
    try:
        index = json.loads(core.file_ref(data['current_used_anchor_rationale_index']).read_text())
        reference = json.loads(used.coverage_reference(index).read_text())
        if used.usage_signature(data) != used.usage_signature(reference) or data['selected_source_groups'] != reference['selected_source_groups']:
            raise ValueError('actual source usage differs from rationale coverage reference')
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
    core.DEFAULT = core.BASE / 'FirstRelease/review-index-v0.11.json'
    core.check = check
    raise SystemExit(core.main())
