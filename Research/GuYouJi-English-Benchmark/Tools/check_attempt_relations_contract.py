#!/usr/bin/env python3
"""Synthetic ordering/matching attempt checks; never grade or infer proficiency."""
import copy
import json
import sys

sys.dont_write_bytecode = True
from validate_attempt_traces import BASE, inspect_trace, snapshot_digest
from validate_item_groups import pre_submit_projection


def refresh(trace):
    digest = snapshot_digest(trace['snapshot']['payload'])
    trace['snapshot']['sha256'] = digest
    for event in trace['events']:
        event['snapshot_sha256'] = digest


def main():
    folder = BASE / 'Attempts/Fixtures-v0.3'
    fixtures = {p.stem: json.loads(p.read_text()) for p in folder.glob('*.json')}
    checks = []

    def reject(name, mutate, fixture='relations-wrong-and-revised', rehash=False):
        trace = copy.deepcopy(fixtures[fixture])
        mutate(trace)
        if rehash:
            refresh(trace)
        result = inspect_trace(trace, {}, {})
        assert not result['structure_valid'], name
        assert result['production_admission'] is False
        checks.append(name)

    for name, trace in fixtures.items():
        result = inspect_trace(trace, {}, {})
        assert result['structure_valid'], name
        assert result['typed_response_records']
        assert result['first_response_event_ids'] == {'i1':'event1','i2':'event2','i3':'event5'}
        assert result['latest_response_event_ids'] == {'i1':'event3','i2':'event4','i3':'event6'}
        assert result['attention_minutes'] is None
        assert 'ordered_element_ids' not in json.dumps(result)
        assert 'right_option_id' not in json.dumps(result)
    reject('unknown_order_member', lambda t:
           t['events'][1]['answer_record']['payload'].update(ordered_element_ids=['other']))
    reject('duplicate_order_member', lambda t:
           t['events'][1]['answer_record']['payload'].update(ordered_element_ids=['blue','blue']))
    reject('unordered_set_object_instead_of_sequence', lambda t:
           t['events'][1]['answer_record']['payload'].update(ordered_element_ids={'blue':1}))
    reject('missing_order_sequence', lambda t:
           t['events'][1]['answer_record']['payload'].pop('ordered_element_ids'))
    reject('order_as_choice', lambda t:
           t['events'][1]['answer_record'].update(payload={'kind':'choice','option_ids':['blue']}))
    reject('matching_as_text', lambda t:
           t['events'][2]['answer_record'].update(payload={'kind':'text','body':'blue'}))
    reject('unknown_matching_right', lambda t:
           t['events'][2]['answer_record']['payload'].update(right_option_id='other'))
    reject('right_array_on_single_left', lambda t:
           t['events'][2]['answer_record']['payload'].update(right_option_id=['label-blue','label-green']))
    reject('empty_string_is_not_unassigned', lambda t:
           t['events'][2]['answer_record']['payload'].update(right_option_id=''))
    reject('spoof_other_left_item_inside_payload', lambda t:
           t['events'][2]['answer_record']['payload'].update(left_item_id='i3'))
    reject('scoring_value_in_payload', lambda t:
           t['events'][1]['answer_record']['payload'].update(marks=1))
    reject('stale_order_item_version', lambda t:
           t['events'][1]['answer_record'].update(item_version='older'))
    reject('cross_item_replacement', lambda t:
           t['events'][4]['answer_record'].update(replaces_event_id='event1'))
    reject('skip_with_empty_match_payload', lambda t:
           t['events'][5]['answer_record'].update(payload={'kind':'matching','right_option_id':None}))
    reject('answer_with_null_record_payload', lambda t:
           t['events'][2]['answer_record'].update(payload=None))
    reject('v02_cannot_accept_relational_payload', lambda t: t.update(contract_version='0.2'))
    reject('missing_order_member_from_frozen_group', lambda t:
           t['snapshot']['payload']['group']['items'][0]['response']['elements'].pop(), rehash=True)
    reject('incomplete_private_order_key', lambda t:
           t['snapshot']['payload']['group']['private_scoring'][0]['accepted_orders'][0].pop(), rehash=True)
    reject('unknown_key_with_fabricated_orders', lambda t:
           t['snapshot']['payload']['group']['private_scoring'][0].update(accepted_orders=[['blue','green','red']]),
           fixture='relations-unknown-keys', rehash=True)
    def option_outside_item(trace):
        response = trace['snapshot']['payload']['group']['items'][1]['response']
        response['right_options'][0]['id'] = 'different-blue'
        trace['events'][2]['answer_record']['payload']['right_option_id'] = 'label-blue'
    reject('right_option_from_another_left_pool', option_outside_item,
           fixture='relations-unknown-keys', rehash=True)

    # Correctness cannot govern whether real entered drafts are retained.
    original = fixtures['relations-wrong-and-revised']
    assert original['events'][3]['answer_record']['payload']['ordered_element_ids'] == ['red','green','blue']
    empty = copy.deepcopy(original)
    empty['events'][1]['answer_record']['payload']['ordered_element_ids'] = []
    assert inspect_trace(empty, {}, {})['structure_valid']
    # Both matching responses reuse label-blue despite the frozen no-reuse task.
    assert original['events'][4]['answer_record']['payload']['right_option_id'] == \
           original['events'][6]['answer_record']['payload']['right_option_id']
    assert inspect_trace(original, {}, {})['structure_valid']
    for order in [['blue','green','red'], ['green','blue','red']]:
        equal = copy.deepcopy(original)
        equal['events'][3]['answer_record']['payload']['ordered_element_ids'] = order
        assert inspect_trace(equal, {}, {})['structure_valid']
        assert equal['events'][3]['answer_record']['payload']['ordered_element_ids'] == order
    group = original['snapshot']['payload']['group']
    projection = json.dumps(pre_submit_projection(group))
    assert 'private_scoring' not in projection and 'accepted_orders' not in projection
    assert 'accepted_pairs' not in projection
    # All0.2 supported payloads are retained in0.3 without rewriting snapshots.
    preserved = 0
    for path in (BASE / 'Attempts/Fixtures-v0.2').glob('*.json'):
        trace = json.loads(path.read_text())
        trace['contract_version'] = '0.3'
        assert inspect_trace(trace, {}, {})['structure_valid']
        preserved += 1
    sentinel = copy.deepcopy(original)
    sentinel['events'][1]['answer_record']['payload']['extra'] = 'RELATION_PRIVATE_SENTINEL'
    report = inspect_trace(sentinel, {}, {})
    assert not report['structure_valid'] and 'RELATION_PRIVATE_SENTINEL' not in json.dumps(report)
    print(json.dumps(dict(positive_fixtures=len(fixtures), negative_rejections=len(checks),
        checks=checks, prior_payload_fixtures_preserved=preserved,
        wrong_partial_and_empty_order_recordable=True, wrong_reused_matching_recordable=True,
        ordered_sequence_not_sorted=True, skipped_and_empty_matching_distinct=True,
        private_keys_not_projected=True, invalid_response_not_echoed=True,
        grading_implemented=False, production_admission=False), indent=2))


if __name__ == '__main__':
    main()
