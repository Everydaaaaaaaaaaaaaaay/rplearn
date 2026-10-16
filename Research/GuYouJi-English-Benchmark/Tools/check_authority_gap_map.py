#!/usr/bin/env python3
"""Check the authority/source/author layers of the fifteen-level research map.

This validates recorded contracts, not source truth or educational validity.
Raw student material remains in ignored, SHA-bound evidence storage.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def read(path):
    return json.loads(path.read_text())


def reference(record):
    paths = [BASE / record['path'], REPO / record['path']]
    path = next((p for p in paths if p.is_file()), None)
    assert path, record['path']
    assert hashlib.sha256(path.read_bytes()).hexdigest() == record['sha256'], path
    return path


def walk_refs(value):
    count = 0
    if isinstance(value, dict):
        if {'path', 'sha256'} <= value.keys():
            reference(value)
            count += 1
        count += sum(walk_refs(v) for v in value.values())
    elif isinstance(value, list):
        count += sum(walk_refs(v) for v in value)
    return count


def source_contracts(groups):
    ids = {g['id']: g for g in groups}
    assert len(ids) == len(groups)
    for group in groups:
        assert group['full_student_input']
        assert not group['is_independent_gold']
        assert group['responses'] == len(group['question_numbers'])
        assert len(set(group['question_numbers'])) == group['responses']
        counts = group['candidates'].get('per_response')
        if counts:
            assert len(counts) == group['responses'] and all(c >= 2 for c in counts)
        key = group['published_key']
        if key is not None:
            assert len(key) == group['responses']
        # The paper itself says sample; it is not an ordinary real-paper closure.
        assert not group['source']['path'].endswith('/primary3-dongcheng.pdf')
    row = ids['p4.fangshan2025.two-picturebanks']
    assert row['responses'] == 10
    assert row['candidates']['banks_are_separate']
    assert row['candidates']['per_response'] == [5] * 10
    assert row['material']['subgroups'] == [
        {'responses': 5, 'pictures': 5, 'shared_phrases': 5},
        {'responses': 5, 'pictures': 5, 'shared_phrases': 5}]
    row = ids['p3.daoli2025.phonicsbank']
    assert row['physical_pages'] == [] and row['preview_printed_student_page'] == 2
    assert row['source_is_one_png_containing_two_printed_student_pages']
    row = ids['advanced.c1.sample1.part3']
    assert row['responses'] == row['material']['given_stems'] == 8
    assert row['material']['answered_examples'] == 1
    assert len(row['given_stems']) == 8 and row['candidates']['printed_choices'] == 0
    assert row['deterministic_admission'].startswith('pending_')
    row = ids['advanced.c1.sample1.part7']
    assert row['kind'] == 'paragraph_gap_insertion'
    assert row['material']['passage'] == 1 and row['responses'] == 6
    assert row['candidates']['shared_paragraphs'] == 7
    assert row['physical_pages'] == [12, 13] and row['published_key'] == list('GDAFCE')
    row = ids['advanced.c1.sample1.part8']
    assert row['material']['article'] == 1 and row['material']['consultant_sections'] == 5
    assert row['responses'] == 10 and row['reuse_rule'] == 'explicit_repeat_allowed'
    assert row['published_key'] == list('DECADBCABE')
    for ident in ['p5.taizhou2025.storybank', 'p5.taizhou2025.phrasebank',
                  'p5.taizhou2025.dialoguebank']:
        row = ids[ident]
        assert row['responses'] == 5 and row['candidates']['shared_entries'] == 6
        assert row['cannot_corroborate_old_8gap_3choice_cloze']
    row = ids['p6.dongcheng2025.closedmixed']
    assert row['responses'] == 5 and row['candidates']['per_response'] == [2, 2, 2, 3, 3]
    assert [len(s['numbers']) for s in row['material']['subgroups']] == [3, 2]


def check(run_path):
    run = read(run_path)
    checked = walk_refs(run)
    atlas = read(reference(run['authority_atlas']))
    source = read(reference(run['selected_source_modes']))
    targets = read(reference(run['original_coverage_target']))
    gaps = read(reference(run['gap_queue']))
    for value in [atlas, source, targets, gaps]:
        checked += walk_refs(value)
    policy = read(reference(run['scope_policy']))
    levels = {r['id'] for r in policy['product_levels']}
    assert len(levels) == 15 and 'kindergarten' not in levels
    assert {r['level'] for r in atlas['levels']} == levels
    authority_ids = {r['id'] for r in atlas['authorities']}
    for row in atlas['levels']:
        assert set(row['authority_ids']) <= authority_ids
        assert not row['per_grade_national_fixed_type_set_claimed']
    source_contracts(source['groups'])
    assert source['new_selected_source_groups'] == len(source['groups'])
    assert source['new_source_responses'] == sum(g['responses'] for g in source['groups'])
    assert source['new_authored_groups'] == 0
    assert targets['currently_complete_originals'] == 76
    assert targets['supported_level_type_cells'] == len(targets['rows'])
    assert len({(r['level'], r['family']) for r in targets['rows']}) == len(targets['rows'])
    assert targets['minimum_new_groups_to_reach_target_if_all_admitted'] == sum(
        r['remaining_originals'] for r in targets['rows'])
    assert all(r['remaining_originals'] == max(0, 3-r['current_complete_originals'])
               for r in targets['rows'])
    assert run['closing_only_from_utc'] == '2026-10-17T03:00:00Z'
    assert run['hard_deadline_utc'] == '2026-10-17T04:00:00Z'
    assert run['automation_id'] == '17-12'
    negative_checks = 0
    for field, value in [('kind', 'shared_insertion'), ('responses', 5)]:
        bad = copy.deepcopy(source['groups'])
        next(g for g in bad if g['id'] == 'advanced.c1.sample1.part7')[field] = value
        try:
            source_contracts(bad)
        except AssertionError:
            negative_checks += 1
        else:
            raise AssertionError('Invalid paragraph contract accepted')
    bad = copy.deepcopy(source['groups'])
    next(g for g in bad if g['id'] == 'p4.fangshan2025.two-picturebanks')[
        'candidates']['per_response'] = [10] * 10
    try:
        source_contracts(bad)
    except AssertionError:
        negative_checks += 1
    else:
        raise AssertionError('Merged candidate banks accepted')
    return {'levels': 15, 'authority_references': len(authority_ids),
            'new_complete_input_modes': len(source['groups']),
            'new_source_responses': source['new_source_responses'],
            'new_authored_groups': 0, 'references_checked': checked,
            'rejected_bad_contracts': negative_checks,
            'all_passed': True,
            'not_independent_gold_or_student_commercial_production_validation': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', type=Path, default=BASE/'AuthorityGap20261017/Run-v0.1.json')
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    result = check(args.run)
    if args.report:
        assert not args.report.exists(), 'Keep versioned check reports immutable'
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(result, ensure_ascii=False))
