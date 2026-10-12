#!/usr/bin/env python3
"""Check annotation coordinate corruption and privacy on original fixtures only."""
import copy
import json
import unicodedata

from annotation_ranges import annotation_range_errors
from validate_item_groups import BASE, pre_submit_projection, semantic_errors, validator_for


def main():
    paths = ['block-annotation-mixed-v03', 'block-annotation-unknown-v03']
    fixtures = {name: json.loads((BASE / 'ItemGroups/Fixtures' / (name + '.json')).read_text())
                for name in paths}

    def errors(value):
        return list(validator_for(value).iter_errors(value)) or semantic_errors(value, {}, {})

    for name, fixture in fixtures.items():
        assert not errors(fixture), name
    baseline = fixtures[paths[0]]
    checks = []

    def reject(label, mutate):
        changed = copy.deepcopy(baseline)
        mutate(changed)
        assert errors(changed), label
        checks.append(label)

    response = lambda g: g['items'][1]['response']
    score = lambda g: g['private_scoring'][1]
    first = lambda g: score(g)['accepted_sets'][0][0]
    reject('stale_material_version', lambda g: response(g)['target_blocks'][0].update(material_version='stale'))
    reject('wrong_literal_digest', lambda g: response(g)['target_blocks'][0].update(text_sha256='0' * 64))
    reject('changed_literal_with_old_digest', lambda g: g['materials'][0]['blocks'][0].update(text='Different text'))
    reject('target_unknown_material', lambda g: response(g)['target_blocks'][0].update(material_id='missing'))
    reject('target_outside_item_scope', lambda g: g['items'][1].update(material_ids=[]))
    reject('target_unknown_block', lambda g: response(g)['target_blocks'][0].update(block_id='missing'))
    reject('target_slot_not_literal', lambda g: response(g)['target_blocks'][0].update(block_id='gb1'))
    reject('duplicate_target_block', lambda g: response(g)['target_blocks'].append(response(g)['target_blocks'][0]))
    reject('target_transcript_not_presented', lambda g: g['materials'][0].update(role='transcript'))
    reject('false_annotation_coordinate_unit', lambda g: response(g).update(coordinate_unit='utf16'))
    reject('implicit_unicode_normalization', lambda g: response(g).update(normalization='NFC'))
    reject('concatenated_filled_surface', lambda g: response(g).update(surface='filled_paragraph'))
    reject('reversed_selection_bounds', lambda g: response(g).update(min_ranges=4, max_ranges=1))
    reject('private_key_in_response_format', lambda g: response(g).update(accepted_sets=score(g)['accepted_sets']))
    reject('annotation_bound_to_gap', lambda g: g['items'][1].update(slot_ids=['gap1']))
    reject('annotation_scope_not_explicit', lambda g: g['items'][1]['response_scope'].update(kind='unknown'))
    reject('text_response_with_annotation_scope', lambda g: g['items'][0]['response_scope'].update(kind='annotation_ranges'))
    reject('annotation_score_on_text_item', lambda g: score(g).update(item_ids=['i1']))
    reject('two_items_for_single_annotation_score', lambda g: score(g).update(item_ids=['i1', 'i2']))
    reject('unknown_annotation_key_as_known_set', lambda g: score(g)['answer_policy'].update(coverage='unknown'))
    reject('reference_examples_used_as_exact_gate', lambda g: score(g)['answer_policy'].update(adjudication='exact_documented_forms'))
    reject('known_coverage_without_evidence', lambda g: score(g)['answer_policy'].update(evidence_ids=[]))
    reject('range_unknown_target', lambda g: first(g).update(block_id='gb1'))
    reject('empty_range', lambda g: first(g).update(end=first(g)['start']))
    reject('reversed_range', lambda g: first(g).update(start=9, end=2))
    reject('negative_range', lambda g: first(g).update(start=-1))
    reject('range_exceeds_literal', lambda g: first(g).update(end=9999))
    reject('boolean_coordinate', lambda g: first(g).update(start=True))
    reject('wrong_selected_text_echo', lambda g: first(g).update(selected_text='sheep'))
    reject('utf16_shift_with_correct_word_echo', lambda g: first(g).update(start=3, end=8))
    reject('duplicate_range', lambda g: score(g)['accepted_sets'][0].append(first(g)))
    reject('overlapping_range', lambda g: score(g)['accepted_sets'][0].append(
        dict(material_id='m1', block_id='left', start=3, end=5, selected_text='ox')))
    reject('same_answer_set_different_order', lambda g: score(g)['accepted_sets'].append(
        list(reversed(score(g)['accepted_sets'][0]))))
    reject('private_ranges_over_maximum', lambda g: response(g).update(max_ranges=1))
    reject('gold_admission', lambda g: g.update(admission='gold'))
    reject('opening_story', lambda g: g.update(opening_story='Unversioned extra text'))

    item = baseline['items'][1]
    reference = score(baseline)['accepted_sets'][0]
    assert not annotation_range_errors(baseline, item, reference)
    assert not annotation_range_errors(baseline, item, [])  # unanswered is not structurally corrupt
    literal = baseline['materials'][0]['blocks'][2]['text']
    word = 'Cafe\u0301'
    start = literal.index(word)
    nfd_range = dict(material_id='m1', block_id='right', start=start,
                     end=start + len(word), selected_text=word)
    assert not annotation_range_errors(baseline, item, [nfd_range])  # not a correctness judgment
    nfc_range = {**nfd_range, 'selected_text': unicodedata.normalize('NFC', word)}
    assert annotation_range_errors(baseline, item, [nfc_range]), 'NFD surface silently normalised'
    assert annotation_range_errors(baseline, item, [{'start': 0}]), 'Incomplete payload accepted'
    assert annotation_range_errors(baseline, item, [{'material_id': [], 'block_id': 'left',
                                                   'start': 0, 'end': 1, 'selected_text': 'x'}])
    assert annotation_range_errors(baseline, item, {'not': 'a list'})
    checks.extend(['raw_NFD_payload_preserved', 'NFC_echo_mismatch_rejected',
                   'incomplete_payload_rejected', 'malformed_identity_rejected', 'non_list_payload_rejected'])
    # A filled slot can add arbitrary width between the unchanged literal blocks.
    for fill in ['a', 'a very long connector', '🙂🙂🙂']:
        surface = baseline['materials'][0]['blocks'][0]['text'] + fill + literal
        assert surface.index('sheep') != reference[1]['start']
        assert not annotation_range_errors(baseline, item, reference)
    checks.append('slot_width_does_not_move_block_coordinates')

    projected = pre_submit_projection(baseline)
    assert projected['items'][1]['response']['target_blocks'] == response(baseline)['target_blocks']
    assert projected['items'][1]['response_scope']['kind'] == 'annotation_ranges'
    private_tokens = ['accepted_sets', 'private_scoring', 'source_key_mappings', 'answer_policy', 'selected_text']
    public_text = json.dumps(projected, ensure_ascii=False)
    assert not any('"' + key + '"' in public_text for key in private_tokens)
    altered = copy.deepcopy(baseline)
    altered['private_scoring'][1]['rule'] = 'Private review policy changed'
    altered['private_scoring'][1]['accepted_sets'] = [[nfd_range]]
    assert not errors(altered)
    assert pre_submit_projection(altered) == projected, 'Private key alters pre-submit view'
    checks.extend(['projection_retains_coordinate_contract', 'private_keys_absent_from_projection',
                   'projection_independent_of_private_answer_changes'])
    print(json.dumps(dict(original_fixtures_passed=len(fixtures), corruption_checks_passed=len(checks),
                          checks=checks, production_admission=False,
                          limitation='Structural coordinates and privacy only; no educational scoring, source gold or learner validation'),
                     ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
