#!/usr/bin/env python3
"""Synthetic typed-response checks; no learner, scoring or server evidence."""
import copy
import json
import sys

sys.dont_write_bytecode = True

from validate_attempt_traces import BASE, inspect_trace, snapshot_digest


def main():
    fixtures = {p.stem: json.loads(p.read_text()) for p in
                (BASE / 'Attempts/Fixtures-v0.2').glob('*.json')}
    checks = []

    def inspect(trace):
        return inspect_trace(trace, {}, {})

    def reject(name, mutate, fixture='annotation-revisions'):
        trace = copy.deepcopy(fixtures[fixture])
        mutate(trace)
        result = inspect(trace)
        assert not result['structure_valid'], name
        assert result['production_admission'] is False
        checks.append(name)

    for name, trace in fixtures.items():
        assert inspect(trace)['structure_valid'], name
    reject('missing_answer_record', lambda t: t['events'][1].pop('answer_record'))
    reject('null_answer_record', lambda t: t['events'][1].update(answer_record=None))
    reject('nonanswer_carries_record', lambda t: t['events'][0].update(answer_record=t['events'][1]['answer_record']))
    reject('stale_item_version', lambda t: t['events'][1]['answer_record'].update(item_version='v0'))
    reject('first_response_revision_not_zero', lambda t: t['events'][1]['answer_record'].update(revision=1))
    reject('first_response_replaces_event', lambda t: t['events'][1]['answer_record'].update(replaces_event_id='event0'))
    reject('revision_gap', lambda t: t['events'][3]['answer_record'].update(revision=3))
    reject('revision_repeats_ordinal', lambda t: t['events'][3]['answer_record'].update(revision=0))
    reject('revision_links_other_item', lambda t: t['events'][3]['answer_record'].update(replaces_event_id='event2'))
    reject('revision_links_old_not_latest', lambda t: t['events'][6]['answer_record'].update(replaces_event_id='event2'))
    reject('skip_carries_payload', lambda t: t['events'][5]['answer_record'].update(payload=t['events'][4]['answer_record']['payload']))
    reject('answered_lacks_payload', lambda t: t['events'][1]['answer_record'].update(payload=None))
    reject('wrong_response_kind', lambda t: t['events'][1]['answer_record'].update(payload={'kind':'text','body':'the'}))
    reject('unknown_slot', lambda t: t['events'][1]['answer_record']['payload']['slots'][0].update(slot_id='other'))
    reject('duplicate_slot', lambda t: t['events'][1]['answer_record']['payload']['slots'].append(copy.deepcopy(t['events'][1]['answer_record']['payload']['slots'][0])))
    reject('missing_slot', lambda t: t['events'][1]['answer_record']['payload'].update(slots=[]))
    reject('range_on_gap_block', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(block_id='gb1'))
    reject('range_wrong_text_echo', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(selected_text='foxes'))
    reject('range_utf16_offset', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(start=3,end=8))
    reject('range_outside_text', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(end=999))
    reject('range_reversed', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(start=7,end=2))
    reject('duplicate_range', lambda t: t['events'][2]['answer_record']['payload']['ranges'].append(copy.deepcopy(t['events'][2]['answer_record']['payload']['ranges'][0])))
    reject('range_extra_private_field', lambda t: t['events'][2]['answer_record']['payload']['ranges'][0].update(score=1))
    reject('unknown_choice', lambda t: t['events'][1]['answer_record']['payload'].update(option_ids=['missing']), 'choice-and-skip')
    reject('multiple_on_single_choice', lambda t: t['events'][1]['answer_record']['payload'].update(option_ids=['a','b']), 'choice-and-skip')
    reject('duplicate_choice', lambda t: t['events'][1]['answer_record']['payload'].update(option_ids=['a','a']), 'choice-and-skip')
    reject('empty_answered_choice', lambda t: t['events'][1]['answer_record']['payload'].update(option_ids=[]), 'choice-and-skip')
    reject('wrong_writing_kind', lambda t: t['events'][1]['answer_record']['payload'].update(kind='text'), 'raw-writing')
    reject('unrequested_personal_content', lambda t: t['events'][1]['answer_record'].update(raw_chat='Unrequested'), 'raw-text')
    reject('event_without_answer_status', lambda t: t['events'][1].update(response_status='not_applicable'))
    reject('postsubmit_revision', lambda t: t['events'][-1].update(kind='answer',item_id='i2',response_status='answered',answer_record=t['events'][6]['answer_record']))

    result = inspect(fixtures['annotation-revisions'])
    assert result['first_response_event_ids'] == {'i1':'event1','i2':'event2'}
    assert result['latest_response_event_ids'] == {'i1':'event3','i2':'event6'}
    # Formats do not judge linguistic correctness or exclude legitimate wrong answers.
    wrong = copy.deepcopy(fixtures['annotation-revisions'])
    wrong['events'][2]['answer_record']['payload']['ranges'] = [dict(
        material_id='m1',block_id='left',start=8,end=13,selected_text='watch')]
    assert inspect(wrong)['structure_valid']
    blank = copy.deepcopy(fixtures['raw-text'])
    blank['events'][1]['answer_record']['payload']['body'] = ''
    assert inspect(blank)['structure_valid']  # Empty entered text differs from explicit skip.
    long = copy.deepcopy(fixtures['raw-text'])
    long['events'][1]['answer_record']['payload']['body'] = 'one two three four five six'
    assert inspect(long)['structure_valid']  # Overlimit response must remain recordable.
    assert fixtures['raw-text']['events'][1]['answer_record']['payload']['body'] == '  a\nCafe\u0301 🦊  '
    # Coherent payload edits remain possible without a server ledger/signature.
    replaced = copy.deepcopy(fixtures['annotation-revisions'])
    replaced['events'][1]['answer_record']['payload']['slots'][0]['text'] = 'edited'
    assert inspect(replaced)['structure_valid']
    # Unsupported speaking cannot masquerade as a text answer.
    spoken = copy.deepcopy(fixtures['raw-writing'])
    item = spoken['snapshot']['payload']['group']['items'][0]
    item['response']['kind'] = 'speaking'
    d = snapshot_digest(spoken['snapshot']['payload'])
    spoken['snapshot']['sha256'] = d
    for event in spoken['events']:
        event['snapshot_sha256'] = d
    assert not inspect(spoken)['structure_valid']
    checks.append('unsupported_speaking_as_text')
    public_report = json.dumps(result,ensure_ascii=False)
    assert 'selected_text' not in public_report and 'payload' not in result
    assert result['attention_minutes'] is None and result['production_admission'] is False
    print(json.dumps(dict(positive_fixtures=len(fixtures),negative_rejections=len(checks),
        negative_cases=checks,raw_text_preserved=True,wrong_answers_recordable=True,
        revision_skip_resume_identity_checked=True,validation_report_omits_raw_responses=True,
        response_history_authentication=False,production_admission=False,
        limitation='Synthetic record consistency only; no real learners, scoring, server privacy or immutable response ledger'),indent=2))


if __name__ == '__main__':
    main()
