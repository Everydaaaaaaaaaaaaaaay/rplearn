#!/usr/bin/env python3
"""Validate synthetic research traces; never infer attention or execute grading.

Requires jsonschema4.25.1. Digest checks are not signatures or trusted history.
Intervals are client activity proxies; clocks from different epochs are not added
into an elapsed span. Overlap within each epoch/category is counted only once.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from jsonschema import Draft202012Validator, FormatChecker
from validate_item_groups import BASE, validator_for, semantic_errors
from annotation_ranges import annotation_range_errors


def schema_error_summary(error, prefix=''):
    """Keep location/constraint, without jsonschema's raw instance or schema dump.

    A failed oneOf may otherwise echo learner text; group errors can include
    private scoring. These reports are diagnostics, not copies of either input.
    """
    location = '/'.join(map(str, error.absolute_path)) or '<root>'
    return f'{prefix}{location}: schema constraint {error.validator} failed'


def response_errors(group, item, response, trace_version='0.2'):
    """Check response identity/coordinates, never correctness or linguistic limits.

    Invalid answers (e.g. too many words) still need recording. Product UX and
    grading must distinguish those from malformed references. Preserve raw text.
    """
    expected, kind = item['response']['kind'], response['kind']
    if trace_version == '0.3' and expected == kind == 'ordering':
        # Partial/empty drafts and wrong order remain actual response evidence.
        members = response['ordered_element_ids']
        declared = {o['id'] for o in item['response']['elements']}
        return [] if len(members) == len(set(members)) and set(members) <= declared \
            else ['Ordering response repeats a member or references an unknown element']
    if trace_version == '0.3' and expected == kind == 'matching':
        option = response['right_option_id']
        # Empty entered response is distinct from skipping the entire item.
        # Wrong reuse across left items is kept for grading, not silently dropped.
        return [] if option is None or option in {o['id'] for o in item['response']['right_options']} \
            else ['Matching response references an unknown right option']
    if expected == 'span_annotation' and kind == expected:
        return annotation_range_errors(group, item, response['ranges'])
    if expected == 'choice' and kind == expected:
        options = set(response['option_ids'])
        if not options <= {o['id'] for o in item['response']['options']}:
            return ['Response references an unknown option']
        if item['response']['selection'] == 'single' and len(options) != 1:
            return ['Single-choice response selects multiple options']
        return []
    if expected == 'text':
        if item['slot_ids'] and kind == 'slot_text':
            ids = [s['slot_id'] for s in response['slots']]
            return [] if len(ids) == len(set(ids)) and set(ids) == set(item['slot_ids']) \
                else ['Slot response must identify every declared slot exactly once']
        if not item['slot_ids'] and kind == 'text':
            return []
    if expected in ('writing', 'translation') and kind == expected:
        return []
    return ['Response format does not match the frozen item or is unsupported by this attempt version']


def snapshot_digest(payload):
    raw = json.dumps(payload, sort_keys=True, ensure_ascii=False, separators=(',', ':'),
                     allow_nan=False).encode('utf-8')
    return hashlib.sha256(raw).hexdigest()


def merged_length(intervals):
    total, previous_end = 0, None
    for start, end in sorted(intervals):
        total += end - start if previous_end is None else max(0, end - max(start, previous_end))
        previous_end = end if previous_end is None else max(end, previous_end)
    return total


def inspect_trace(trace, sources, acquisitions, expected_digest=None):
    def nonfinite(value):
        if isinstance(value, dict):
            return any(nonfinite(v) for v in value.values())
        if isinstance(value, list):
            return any(nonfinite(v) for v in value)
        return isinstance(value, float) and not math.isfinite(value)
    if nonfinite(trace):
        return dict(structure_valid=False, errors=['Non-finite numeric value in trace'], production_admission=False)
    version = trace.get('contract_version')
    filename = {'0.1': 'AttemptTrace.schema.json', '0.2': 'AttemptTrace-v0.2.schema.json',
                '0.3': 'AttemptTrace-v0.3.schema.json'}.get(version) \
        if isinstance(version, str) else None
    if filename is None:
        return dict(structure_valid=False, errors=['Unsupported attempt contract version'], production_admission=False)
    schema = json.loads((BASE / 'Attempts' / filename).read_text())
    Draft202012Validator.check_schema(schema)
    errors = [schema_error_summary(e) for e in
              Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(trace)]
    if errors:
        return {'structure_valid': False, 'errors': errors, 'production_admission': False}

    def require(condition, message):
        if not condition:
            errors.append(message)

    snapshot = trace['snapshot']
    payload, group = snapshot['payload'], snapshot['payload']['group']
    try:
        group_errors = list(validator_for(group).iter_errors(group))
    except (ValueError, TypeError):
        group_errors = ['Unsupported group snapshot contract']
    errors += [schema_error_summary(e, 'group snapshot: ') if not isinstance(e, str)
               else e for e in group_errors]
    if group_errors:
        return {'structure_valid': False, 'errors': errors, 'production_admission': False}
    errors += semantic_errors(group, sources, acquisitions)
    require(group['administration']['submission_boundary'] == 'whole_group',
            'This trace draft only models whole-group submission')
    require(snapshot['sha256'] == snapshot_digest(payload), 'Frozen payload digest mismatch')
    require(expected_digest is None or snapshot['sha256'] == expected_digest,
            'Payload disagrees with externally supplied expected digest')
    item_index = {i['id']: i for i in group['items']}
    items = set(item_index)
    supports = {s['id']: s for s in group['administration']['supports']}
    epochs = {e['id'] for e in trace['epochs']}
    require(len(epochs) == len(trace['epochs']), 'Duplicate clock epoch')
    event_ids, sequences, previous_times = set(), [], {}
    answers, submitted, started, closed, assisted = {}, False, False, False, False
    revisions, first_responses = {}, {}
    for event in trace['events']:
        require(event['id'] not in event_ids, 'Duplicate event identity')
        event_ids.add(event['id'])
        sequences.append(event['sequence'])
        require(event['snapshot_sha256'] == snapshot['sha256'], 'Event belongs to a different frozen payload')
        epoch, time = event['epoch_id'], event['monotonic_ms']
        require((epoch is None) == (time is None), 'Unknown clock must retain null epoch and time together')
        if epoch is not None and time is not None:
            require(epoch in epochs, 'Unknown event clock epoch')
            require(time >= previous_times.get(epoch, 0), 'Monotonic time moved backwards within an epoch')
            previous_times[epoch] = time
        kind, item = event['kind'], event['item_id']
        require(item is None or item in items, 'Event references an unknown item')
        require(kind == 'answer' or event['response_status'] == 'not_applicable',
                'Nonanswer event contains response status')
        if version in ('0.2', '0.3'):
            require(kind == 'answer' or event['answer_record'] is None,
                    'Nonanswer event contains a private answer record')
        require(kind == 'support_exposed' or event['support_id'] is None,
                'Nonsupport event references a support')
        if kind == 'start':
            require(not started and not closed, 'Attempt started more than once')
            started = True
        else:
            require(started and not closed, 'Event before start or after terminal state')
        if kind == 'answer':
            require(item is not None and event['response_status'] != 'not_applicable',
                    'Answer lacks item/status')
            require(not submitted, 'Answer modified after whole-group submit')
            if version in ('0.2', '0.3'):
                record = event['answer_record']
                require(record is not None, 'Answer event lacks typed record')
                if record is not None:
                    previous = revisions.get(item)
                    require(record['revision'] == (0 if previous is None else previous['revision'] + 1),
                            'Answer revision is not the next per-item ordinal')
                    require(record['replaces_event_id'] == (None if previous is None else previous['event_id']),
                            'Answer revision does not replace the immediately previous event for this item')
                    if item in item_index:
                        require(record['item_version'] == item_index[item]['version'], 'Answer belongs to a stale item version')
                    if event['response_status'] == 'skipped':
                        require(record['payload'] is None, 'Skipped answer must retain null payload')
                    elif event['response_status'] == 'answered':
                        require(record['payload'] is not None, 'Answered event lacks actual response payload')
                        if record['payload'] is not None and item in item_index:
                            errors += response_errors(group, item_index[item], record['payload'], version)
                    revisions[item] = dict(revision=record['revision'], event_id=event['id'],
                                           status=event['response_status'])
                    first_responses.setdefault(item, event['id'])
            # Revision events replace the current draft, without inventing first-answer mastery.
            if item is not None:
                answers[item] = event['response_status']
        elif kind == 'submit_group':
            require(not submitted and answers.keys() == items,
                    'Whole-group submission lacks explicit answer/skip for every item or repeats submit')
            submitted = True
        elif kind == 'support_exposed':
            support = supports.get(event['support_id'])
            require(support is not None, 'Exposure references unknown support')
            if support is not None:
                if support['release'] == 'after_group_submit':
                    require(submitted, 'Post-submit support released before group submission')
                if not submitted:
                    assisted = True
        elif kind == 'feedback_exposed':
            require(group['administration']['feedback_release'] != 'not_available',
                    'Feedback exposed although frozen administration has none')
            if group['administration']['mode'] in ('diagnostic', 'ranked') or \
                    group['administration']['feedback_release'] == 'after_group_submit':
                require(submitted, 'Feedback leaked before whole-group submission')
            if not submitted:
                assisted = True
        elif kind in ('close', 'abandon'):
            require(kind == 'abandon' or submitted, 'Closed as completed without whole-group submit')
            closed = True
        if kind != 'answer':
            require(item is None, 'Group event incorrectly scoped to one item')
    require(sequences == sorted(set(sequences)), 'Sequence must be unique and strictly increasing')
    require(trace['events'][0]['kind'] == 'start', 'First event must freeze/start the attempt')
    if group['administration']['mode'] in ('diagnostic', 'ranked'):
        require(not assisted, 'Diagnostic/ranked trace contains pre-submit assistance')

    interval_ids, per_epoch_category, per_epoch_all = set(), {}, {}
    epoch_times = {epoch: [e['monotonic_ms'] for e in trace['events']
                          if e['epoch_id'] == epoch and e['monotonic_ms'] is not None] for epoch in epochs}
    for interval in trace['intervals']:
        require(interval['id'] not in interval_ids, 'Duplicate timing interval')
        interval_ids.add(interval['id'])
        epoch = interval['epoch_id']
        require(epoch in epochs, 'Interval references unknown clock epoch')
        require(interval['start_ms'] < interval['end_ms'], 'Timing interval is empty/reversed')
        if 'media_playback' in interval['phases']:
            require(any(a['availability'] == 'acquired' and a['media_type'] in ('audio', 'video')
                        for a in group['assets']), 'Playback phase has no acquired media asset')
        times = epoch_times.get(epoch, [])
        require(bool(times) and min(times) <= interval['start_ms'] < interval['end_ms'] <= max(times),
                'Interval extends outside recorded event time bounds for its epoch')
        pair = interval['start_ms'], interval['end_ms']
        per_epoch_category.setdefault((epoch, interval['category']), []).append(pair)
        per_epoch_all.setdefault(epoch, []).append(pair)
    # Mutually exclusive activity classes cannot claim the same time; phases may overlap.
    for epoch, pairs in per_epoch_all.items():
        category_sum = sum(merged_length(v) for (e, _), v in per_epoch_category.items() if e == epoch)
        require(math.isclose(category_sum, merged_length(pairs), rel_tol=1e-12, abs_tol=1e-8),
                'Timing categories overlap and double-count elapsed time')
    durations = {f'{epoch}/{category}': merged_length(pairs)
                 for (epoch, category), pairs in per_epoch_category.items()}
    history = payload['family_history_status']
    unassisted = 'eligible_under_recorded_conditions' if history == 'verified_no_prior_exposure' \
        and trace['round_ordinal'] == 0 and not assisted else 'ineligible_or_history_unknown'
    if errors:
        unassisted = 'invalid_record_no_evidence'
    return dict(structure_valid=not errors, errors=errors, submitted=submitted, terminal=closed,
                unassisted_condition_status=unassisted, duration_ms_by_epoch_category=durations,
                cross_epoch_elapsed_ms=None, attention_minutes=None,
                incomplete_or_abandoned=not submitted or not closed,
                external_expected_digest_supplied=expected_digest is not None,
                unknown_clock_event_ids=[e['id'] for e in trace['events'] if e['epoch_id'] is None],
                typed_response_records=version in ('0.2', '0.3'),
                first_response_event_ids=first_responses,
                latest_response_event_ids={i: r['event_id'] for i, r in revisions.items()},
                production_admission=False,
                limitation='Research record consistency only; digests do not authenticate server history; no attention, grading, rewards or learner calibration established')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('traces', type=Path, nargs='+')
    parser.add_argument('--expected-digest')
    args = parser.parse_args()
    if args.expected_digest and len(args.traces) != 1:
        parser.error('One external expected digest requires exactly one trace')
    sources = {r['id']: r for r in json.loads((BASE / 'Registry/sources.json').read_text())['sources']}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    reports = []
    for path in args.traces:
        try:
            result = inspect_trace(json.loads(path.read_text()), sources, acquisitions, args.expected_digest)
        except (OSError, ValueError) as exc:
            result = dict(structure_valid=False, errors=[str(exc)], production_admission=False)
        reports.append({'path': str(path), **result})
    print(json.dumps({'traces': reports}, ensure_ascii=False, indent=2, allow_nan=False))
    raise SystemExit(0 if all(r['structure_valid'] for r in reports) else 1)


if __name__ == '__main__':
    main()
