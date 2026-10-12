#!/usr/bin/env python3
"""Exercise representation failures that could silently corrupt research groups.

All examples are original structural fixtures, never exam gold or learner data.
"""
import copy
import json
import sys

sys.dont_write_bytecode = True

from validate_item_groups import BASE, semantic_errors, pre_submit_projection, validator_for


def main():
    fixtures = {p.stem: json.loads(p.read_text()) for p in
                (BASE / 'ItemGroups/Fixtures').glob('*.json')}

    def errors(group):
        try:
            result = list(validator_for(group).iter_errors(group))
        except ValueError as exc:
            return [str(exc)]
        return result or semantic_errors(group, {}, {})

    for name, group in fixtures.items():
        assert not errors(group), f'Positive structural fixture rejected: {name}'
    checks = []

    def reject(name, fixture, mutate):
        group = copy.deepcopy(fixtures[fixture])
        mutate(group)
        assert errors(group), f'Invalid group accepted: {name}'
        checks.append(name)

    reject('duplicate_item', 'reading-four', lambda g: g['items'].append(g['items'][0]))
    reject('unknown_material', 'reading-four', lambda g: g['items'][0].update(material_ids=['missing']))
    reject('wrong_scoring_backreference', 'reading-four', lambda g: g['items'][0].update(scoring_id='s2'))
    reject('unknown_option_key', 'reading-four', lambda g: g['private_scoring'][0].update(accepted_option_ids=['missing']))
    reject('single_choice_multiple_keys', 'reading-four', lambda g: g['private_scoring'][0].update(accepted_option_ids=['a','b']))
    reject('duplicate_option', 'reading-four', lambda g: g['items'][0]['response']['options'].append(g['items'][0]['response']['options'][0]))
    reject('orphan_slot', 'cloze-15', lambda g: g['items'][0].update(slot_ids=[]))
    reject('slot_outside_material', 'cloze-10', lambda g: g['items'][0].update(slot_ids=['missing']))
    reject('duplicated_slot_binding', 'cloze-10', lambda g: g['items'][1].update(slot_ids=['gap1']))
    reject('coupled_tuple_wrong_arity', 'coupled-text', lambda g: g['private_scoring'][0]['accepted_tuples'].append(['red']))
    reject('segments_total_mismatch', 'segmented', lambda g: g['private_scoring'][0]['possible_source_marks'].update(value=3))
    reject('rubric_reversed_band', 'writing-rubric', lambda g: g['private_scoring'][0]['dimensions'][0]['bands'][0].update(minimum_marks=4))
    reject('rubric_unknown_assigned_band', 'writing-rubric', lambda g: g['private_scoring'][0]['scored_examples'].append(dict(id='bad',response_private_ref='private-demo',assigned_band_ids=['missing'],evidence_ids=['fixture.authorship'])))
    reject('unacquired_asset_fake_location', 'listening-unacquired', lambda g: g['assets'][0].update(private_locator='fake.mp3'))
    reject('acquired_asset_without_digest', 'listening-unacquired', lambda g: g['assets'][0].update(availability='acquired'))
    reject('asset_unknown_reference', 'listening-unacquired', lambda g: g['materials'][0]['blocks'][0].update(asset_id='missing'))
    reject('unknown_evidence', 'reading-four', lambda g: g['items'][0].update(evidence_ids=['missing']))
    reject('unknown_claim_fabricated_value', 'reading-four', lambda g: g['review']['learner_calibration'].update(value='passed'))
    reject('known_claim_without_evidence', 'reading-four', lambda g: g['review']['independent'].update(status='verified',value='passed',evidence_ids=[]))
    reject('authorship_as_independent_review', 'reading-four', lambda g: g['review']['independent'].update(status='verified',value='passed',evidence_ids=['fixture.authorship']))
    reject('early_diagnostic_feedback', 'reading-four', lambda g: g['administration'].update(feedback_release='after_item_submit',submission_boundary='per_item'))
    reject('assisted_as_unassisted', 'reading-four', lambda g: g['administration'].update(later_related_items_count_as_unassisted=True))
    reject('early_hint_leak', 'reading-four', lambda g: g['administration']['supports'].append(dict(id='hint1',kind='hint',reveals_related_item_ids=['i2'],release='on_request',content_private_ref='private-demo')))
    reject('opening_story_not_required_or_allowed', 'reading-four', lambda g: g.update(opening_story='Extra unversioned story'))
    reject('gold_or_production_admission', 'reading-four', lambda g: g.update(admission='gold'))
    reject('unacquired_source_content', 'reading-four', lambda g: g['evidence'][0].update(origin=dict(kind='source_record',source_id='missing',acquisition_id='missing',variant='paper',locator='page1')))
    reject('unsupported_contract_version', 'partial-response-reference', lambda g: g.update(contract_version='9.9'))
    reject('nonexhaustive_exact_rejection', 'partial-response-reference', lambda g: g['private_scoring'][0]['answer_policy'].update(adjudication='exact_documented_forms'))
    reject('unknown_exact_rejection', 'partial-response-reference', lambda g: g['private_scoring'][0]['answer_policy'].update(coverage='unknown',adjudication='exact_documented_forms'))
    reject('coverage_without_evidence', 'partial-response-reference', lambda g: g['private_scoring'][0]['answer_policy'].update(evidence_ids=[]))
    reject('missing_response_scope', 'partial-response-reference', lambda g: g['items'][0].pop('response_scope'))
    reject('scope_wrong_slot', 'partial-response-reference', lambda g: g['items'][0]['response_scope'].update(slot_ids=['missing']))
    reject('scope_without_evidence', 'partial-response-reference', lambda g: g['items'][0]['response_scope'].update(evidence_ids=[]))
    reject('slot_scope_as_whole_answer', 'partial-response-reference', lambda g: g['items'][0]['response_scope'].update(kind='whole_response'))
    reject('span_wrong_end', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(source_span=[0,9]))
    reject('span_outside_source', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(source_span=[0,9999]))
    reject('span_reversed', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(source_span=[8,0]))
    reject('silent_key_truncation_as_identity', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(operation='identity',source_span=None))
    reject('unresolved_fabricated_form', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(operation='unresolved',source_span=None))
    reject('source_mapping_wrong_item', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'][0].update(item_id='missing'))
    reject('mapped_form_not_documented', 'partial-response-reference', lambda g: g['private_scoring'][0].update(accepted_forms=['Where was']))
    reject('duplicated_source_mapping', 'partial-response-reference', lambda g: g['private_scoring'][0]['source_key_mappings'].append(copy.deepcopy(g['private_scoring'][0]['source_key_mappings'][0])))
    exhaustive = copy.deepcopy(fixtures['partial-response-reference'])
    exhaustive['private_scoring'][0]['answer_policy'].update(coverage='exhaustive_documented',
        adjudication='exact_documented_forms',reason='Synthetic exact-form task expressly limits the demonstration to the documented form')
    assert not errors(exhaustive)
    exhaustive['items'][0]['response_scope']['kind'] = 'unknown'
    assert errors(exhaustive), 'Unknown scope allowed exact matching'
    checks.append('unknown_scope_exact_matching')
    choice_slots = copy.deepcopy(fixtures['cloze-10'])
    choice_slots.update(contract_version='0.2', id='fixture.choice-slot-scope')
    for item in choice_slots['items']:
        item['response'] = dict(kind='choice', selection='single', options=[
            dict(id='a', text='Original synthetic choice one'),
            dict(id='b', text='Original synthetic choice two')])
        item['response_scope'] = dict(kind='option_ids', slot_ids=item['slot_ids'][:],
            evidence_ids=['fixture.authorship'], reason='Select a stable option identity for the bound cloze gap')
    choice_slots['private_scoring'] = [{**{k: score[k] for k in
        ('id', 'item_ids', 'possible_source_marks', 'evidence_ids')},
        'kind': 'choice', 'accepted_option_ids': ['a'], 'multiple_selection_rule': 'exact_set',
        'rule': 'Synthetic option identity demonstration only'} for score in choice_slots['private_scoring']]
    assert not errors(choice_slots), 'Choice cloze cannot bind explicit gaps in contract0.2'
    choice_slots['items'][0]['response_scope']['kind'] = 'slot_only'
    assert errors(choice_slots), 'Choice response falsely declared free text slot-only'
    checks.append('choice_gap_as_free_text_scope')

    long_group = copy.deepcopy(fixtures['reading-four'])
    long_group['materials'][0]['blocks'][0]['text'] = 'Original long structural placeholder. ' * 100
    for n in range(5, 20):
        item, score = copy.deepcopy(long_group['items'][0]), copy.deepcopy(long_group['private_scoring'][0])
        item.update(id=f'i{n}', scoring_id=f's{n}')
        score.update(id=f's{n}', item_ids=[f'i{n}'])
        long_group['items'].append(item)
        long_group['private_scoring'].append(score)
    assert not errors(long_group), 'Long text or19items silently constrained to production legacy limits'

    private = copy.deepcopy(fixtures['writing-rubric'])
    sentinel = 'PRIVATE_SENTINEL_DO_NOT_PROJECT'
    private['private_scoring'][0]['overall_rule'] = sentinel
    private['evidence'][0]['note'] = sentinel
    private['rights']['reason'] = sentinel
    private['items'][0]['response']['interaction_protocol'] = dict(
        status='provisional', value={'hidden_key': sentinel}, reason='Private administration note',
        evidence_ids=['fixture.authorship'])
    private['administration']['supports'].append(dict(id='h1',kind='hint',
        reveals_related_item_ids=['i1'],release='after_group_submit',content_private_ref=sentinel))
    transcript = copy.deepcopy(private['materials'][0])
    transcript.update(id='transcript1', role='transcript')
    transcript['blocks'][0]['text'] = sentinel
    private['materials'].append(transcript)
    assert not errors(private)
    projection = pre_submit_projection(private)
    assert sentinel not in json.dumps(projection), 'Private scoring/audit/transcript leaked by structural projection'
    projection['items'][0]['instruction'] = 'Mutated public view'
    assert private['items'][0]['instruction'] != 'Mutated public view'
    scoped = copy.deepcopy(fixtures['partial-response-reference'])
    scoped['private_scoring'][0]['source_key_mappings'][0]['reason'] = sentinel
    scoped['items'][0]['response_scope']['reason'] = sentinel
    assert not errors(scoped)
    scoped_projection = pre_submit_projection(scoped)
    assert sentinel not in json.dumps(scoped_projection)
    assert 'source_key_form' not in json.dumps(scoped_projection)
    assert scoped_projection['items'][0]['response_scope'] == {'kind':'slot_only','slot_ids':['gap1']}
    print(json.dumps({'positive_fixtures': len(fixtures), 'negative_rejections': len(checks),
        'negative_cases': checks, 'long_text_and_19_items': 'accepted_without_truncation',
        'private_structural_projection': 'sentinel_excluded_copy_independent',
        'limitation': 'No educational, semantic answer-leakage, real media, grading or production validation'}, indent=2))


if __name__ == '__main__':
    main()
