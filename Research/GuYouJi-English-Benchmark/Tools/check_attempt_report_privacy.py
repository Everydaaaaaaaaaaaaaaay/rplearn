#!/usr/bin/env python3
"""Check that invalid attempt reports do not echo raw answers/private scoring.

Synthetic sentinels test diagnostics only, not a production privacy boundary.
Record IDs and file paths remain diagnostic metadata and may themselves be
identifying in a real deployment; service access/redaction still needs review.
"""
import copy
import json
import sys

sys.dont_write_bytecode = True
from validate_attempt_traces import BASE, inspect_trace, snapshot_digest


def refresh(trace):
    digest = snapshot_digest(trace['snapshot']['payload'])
    trace['snapshot']['sha256'] = digest
    for event in trace['events']:
        event['snapshot_sha256'] = digest


def main():
    fixtures = {p.stem: json.loads(p.read_text()) for p in
                (BASE / 'Attempts/Fixtures-v0.2').glob('*.json')}
    marker = 'RESEARCH_PRIVATE_SENTINEL_🦊'
    checks = []

    def reject_without_echo(name, mutate, fixture='raw-text', refresh_snapshot=False):
        trace = copy.deepcopy(fixtures[fixture])
        # Deliberately store the marker in legitimate private content too.
        if fixture == 'raw-text':
            trace['events'][1]['answer_record']['payload']['body'] = marker
        mutate(trace)
        if refresh_snapshot:
            refresh(trace)
        result = inspect_trace(trace, {}, {})
        assert not result['structure_valid'], name
        assert result['production_admission'] is False
        rendered = json.dumps(result, ensure_ascii=False)
        assert marker not in rendered, name
        assert 'answer_record' not in result and 'snapshot' not in result
        checks.append(name)

    reject_without_echo('extra_response_property', lambda t:
                        t['events'][1]['answer_record']['payload'].update(extra=marker))
    reject_without_echo('wrong_body_type', lambda t:
                        t['events'][1]['answer_record']['payload'].update(body=[marker]))
    reject_without_echo('wrong_payload_kind', lambda t:
                        t['events'][1]['answer_record']['payload'].update(kind=marker))
    reject_without_echo('extra_private_record_property', lambda t:
                        t['events'][1]['answer_record'].update(unrequested=marker))
    reject_without_echo('extra_event_property', lambda t: t['events'][1].update(extra=marker))
    reject_without_echo('unsupported_version', lambda t: t.update(contract_version=marker))
    reject_without_echo('unhashable_version_array', lambda t: t.update(contract_version=[marker]))
    reject_without_echo('unhashable_version_object', lambda t: t.update(contract_version={'extra':marker}))
    reject_without_echo('group_scoring_extra_property', lambda t:
                        t['snapshot']['payload']['group']['private_scoring'][0].update(extra=marker),
                        refresh_snapshot=True)
    reject_without_echo('group_scoring_bad_kind', lambda t:
                        t['snapshot']['payload']['group']['private_scoring'][0].update(kind=marker),
                        refresh_snapshot=True)
    reject_without_echo('group_material_wrong_block_type', lambda t:
                        t['snapshot']['payload']['group']['materials'][0]['blocks'][0].update(kind=marker),
                        refresh_snapshot=True)
    reject_without_echo('group_unhashable_version', lambda t:
                        t['snapshot']['payload']['group'].update(contract_version=[marker]),
                        refresh_snapshot=True)
    reject_without_echo('duplicate_choice_schema_echo', lambda t:
                        t['events'][1]['answer_record']['payload'].update(option_ids=[marker,marker]),
                        fixture='choice-and-skip')
    reject_without_echo('wrong_annotation_echo', lambda t:
                        t['events'][2]['answer_record']['payload']['ranges'][0].update(selected_text=marker),
                        fixture='annotation-revisions')
    valid = copy.deepcopy(fixtures['raw-text'])
    valid['events'][1]['answer_record']['payload']['body'] = marker
    result = inspect_trace(valid, {}, {})
    assert result['structure_valid']
    assert marker not in json.dumps(result, ensure_ascii=False)
    print(json.dumps(dict(invalid_cases=len(checks), checks=checks,
        valid_private_text_omitted=True, invalid_private_values_omitted=True,
        identifiers_and_paths_are_not_anonymized=True, production_admission=False,
        limitation='Synthetic diagnostics only; no production authorization, retention or anonymization established'), indent=2))


if __name__ == '__main__':
    main()
