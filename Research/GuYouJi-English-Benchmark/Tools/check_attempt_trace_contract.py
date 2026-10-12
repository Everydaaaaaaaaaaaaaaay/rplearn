#!/usr/bin/env python3
"""Exercise frozen research attempt, exposure and clock failures synthetically."""
import copy
import json
import sys

sys.dont_write_bytecode = True

from validate_attempt_traces import BASE, inspect_trace, snapshot_digest


def main():
    fixtures = {p.stem: json.loads(p.read_text()) for p in
                (BASE / 'Attempts/Fixtures').glob('*.json')}

    def inspect(trace, expected=None):
        return inspect_trace(trace, {}, {}, expected)

    for name, trace in fixtures.items():
        assert inspect(trace)['structure_valid'], name
    checks = []

    def reject(name, mutate, fixture='completed-first-group'):
        trace = copy.deepcopy(fixtures[fixture])
        mutate(trace)
        result = inspect(trace)
        assert not result['structure_valid'], name
        assert result['production_admission'] is False
        if 'unassisted_condition_status' in result:
            assert result['unassisted_condition_status'] == 'invalid_record_no_evidence'
        checks.append(name)

    reject('frozen_question_changed', lambda t: t['snapshot']['payload']['group']['items'][0].update(instruction='Edited after starting'))
    reject('frozen_reward_policy_changed', lambda t: t['snapshot']['payload'].update(reward_policy_version='v2'))
    reject('event_other_snapshot', lambda t: t['events'][2].update(snapshot_sha256='0'*64))
    reject('duplicate_event', lambda t: t['events'][2].update(id=t['events'][1]['id']))
    reject('duplicate_sequence', lambda t: t['events'][2].update(sequence=1))
    reject('backwards_sequence', lambda t: t['events'][2].update(sequence=99))
    reject('unknown_item', lambda t: t['events'][2].update(item_id='missing'))
    reject('unknown_epoch', lambda t: t['events'][2].update(epoch_id='missing'))
    reject('clock_reset_inside_same_epoch', lambda t: t['events'][3].update(monotonic_ms=0))
    reject('unknown_clock_with_time', lambda t: t['events'][2].update(epoch_id=None))
    reject('known_epoch_without_time', lambda t: t['events'][2].update(monotonic_ms=None))
    reject('answer_status_absent', lambda t: t['events'][2].update(response_status='not_applicable'))
    reject('before_group_feedback', lambda t: t['events'][1].update(kind='feedback_exposed'))
    reject('submit_missing_answer', lambda t: t['events'].pop(2))
    reject('repeat_submit', lambda t: t['events'][7].update(kind='submit_group'))
    reject('post_submit_answer', lambda t: t['events'][7].update(kind='answer',item_id='i1',response_status='answered'))
    reject('close_without_submit', lambda t: t['events'][-1].update(kind='close'), 'abandoned-history-unknown')
    reject('event_after_terminal', lambda t: t['events'].append({**t['events'][-1], 'id':'after-close','sequence':100,'kind':'render','monotonic_ms':1100}))
    reject('repeat_start', lambda t: t['events'][1].update(kind='start'))
    reject('unknown_support', lambda t: t['events'][1].update(kind='support_exposed',support_id='missing'))
    reject('response_on_group_event', lambda t: t['events'][1].update(response_status='answered'))
    reject('group_event_wrong_item_scope', lambda t: t['events'][1].update(item_id='i1'))
    reject('duplicate_timing_interval', lambda t: t['intervals'].append(copy.deepcopy(t['intervals'][0])))
    reject('interval_outside_event_bounds', lambda t: t['intervals'][0].update(end_ms=2000))
    reject('reversed_interval', lambda t: t['intervals'][0].update(end_ms=0))
    reject('timing_category_overlap', lambda t: t['intervals'][1].update(category='background'))
    reject('playback_without_acquired_media', lambda t: t['intervals'][1].update(phases=['media_playback']))
    reject('nonfinite_event_time', lambda t: t['events'][2].update(monotonic_ms=float('nan')))
    reject('nonfinite_interval', lambda t: t['intervals'][0].update(end_ms=float('inf')))
    reject('extra_raw_chat_field', lambda t: t.update(raw_chat_text='Unrequested personal content'))

    good = fixtures['completed-first-group']
    result = inspect(good, good['snapshot']['sha256'])
    assert result['structure_valid'] and result['external_expected_digest_supplied']
    assert result['duration_ms_by_epoch_category'] == {
        'epoch1/foreground_activity_proxy':700, 'epoch1/wait':300}
    assert result['attention_minutes'] is None
    assert not inspect(good, '0'*64)['structure_valid']
    checks.append('externally_expected_snapshot_mismatch')

    replaced = copy.deepcopy(good)
    replaced['snapshot']['payload']['reward_policy_version'] = 'replacement-policy'
    replaced['snapshot']['sha256'] = snapshot_digest(replaced['snapshot']['payload'])
    for event in replaced['events']:
        event['snapshot_sha256'] = replaced['snapshot']['sha256']
    assert inspect(replaced)['structure_valid']  # Self-consistency is not authentication.
    assert not inspect(replaced, good['snapshot']['sha256'])['structure_valid']
    checks.append('coherent_replacement_vs_external_anchor')

    retried = copy.deepcopy(good)
    retried['round_ordinal'] = 1
    assert inspect(retried)['unassisted_condition_status'] == 'ineligible_or_history_unknown'
    exposed = copy.deepcopy(good)
    exposed['snapshot']['payload']['family_history_status'] = 'known_exposed'
    exposed['snapshot']['sha256'] = snapshot_digest(exposed['snapshot']['payload'])
    for event in exposed['events']:
        event['snapshot_sha256'] = exposed['snapshot']['sha256']
    assert inspect(exposed)['unassisted_condition_status'] == 'ineligible_or_history_unknown'
    resumed = inspect(fixtures['resumed-new-clock-epoch'])
    assert resumed['structure_valid'] and resumed['cross_epoch_elapsed_ms'] is None
    assert resumed['duration_ms_by_epoch_category'] == {
        'epoch1/foreground_activity_proxy':400, 'epoch2/foreground_activity_proxy':400}
    unknown_clock = copy.deepcopy(good)
    unknown_clock['events'][2].update(epoch_id=None,monotonic_ms=None)
    assert inspect(unknown_clock)['structure_valid']
    assert inspect(unknown_clock)['unknown_clock_event_ids'] == ['event2']
    practice = copy.deepcopy(good)
    practice_group = practice['snapshot']['payload']['group']
    practice_group['administration']['mode'] = 'practice'
    practice_group['administration']['supports'].append(dict(id='original.hint',kind='hint',
        reveals_related_item_ids=['i1','i2','i3','i4'],release='on_request',
        content_private_ref='Original synthetic hint demonstration'))
    practice['snapshot']['sha256'] = snapshot_digest(practice['snapshot']['payload'])
    for event in practice['events']:
        event['snapshot_sha256'] = practice['snapshot']['sha256']
    practice['events'][1].update(kind='support_exposed',support_id='original.hint')
    result = inspect(practice)
    assert result['structure_valid'] and result['unassisted_condition_status'] == 'ineligible_or_history_unknown'
    practice_group['administration']['supports'][0]['release'] = 'after_group_submit'
    practice['snapshot']['sha256'] = snapshot_digest(practice['snapshot']['payload'])
    for event in practice['events']:
        event['snapshot_sha256'] = practice['snapshot']['sha256']
    assert not inspect(practice)['structure_valid']
    checks.append('postsubmit_support_released_early')
    print(json.dumps(dict(positive_fixtures=len(fixtures), negative_rejections=len(checks),
        negative_cases=checks, overlap_counted_once=True, epochs_kept_separate=True,
        retries_and_prior_exposure_not_unassisted=True, attention_estimate=None,
        coherent_rewrite_without_external_anchor='Self-consistent but not authenticated',
        production_admission=False, limitation='Synthetic consistency cases only; no real server, learner, grading or reward evidence'),indent=2))


if __name__ == '__main__':
    main()
