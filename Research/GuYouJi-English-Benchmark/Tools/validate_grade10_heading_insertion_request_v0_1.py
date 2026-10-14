#!/usr/bin/env python3
"""Verify the currently authored heading-gap request, not English uniqueness."""
import argparse
import json
import re
from pathlib import Path
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref


def check(request):
    checked = []
    try:
        if type(request['grade']) is not int or request['grade'] != 10:
            raise ValueError('grade must be integer10')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade10-v0.3.md' or request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade10-wenzhou2025-public-groups-v0.1.json':
            raise ValueError('wrong specification/source catalogue')
        file_ref(request['specification'])
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] != 'g10.wenzhou2025.insertion' or request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('unsupported source mode or wrong parent')
        if canonical(request['source_format']) != canonical({'items': 5, 'features': group['features']}) or canonical(request['positive_source_reference_numbers']) != canonical(group['question_numbers']):
            raise ValueError('original format/numbering differs')
        if canonical(request['source_heading_number_to_target_item']) != canonical({'40': 5}) or request['authored_once_rule_is_source_explicit'] is not False:
            raise ValueError('heading mapping lost or authored once rule wrongly attributed')
        acqs = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent not PDF')
        checked.append(group['source_paper_acquisition_id'])
        detail_path = cached(acqs[source['private_review_acquisition_id']])
        if digest(detail_path) != source['private_review_sha256']:
            raise ValueError('private source review differs')
        detail = next(g for g in json.loads(detail_path.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != group['question_numbers'] or any(not r['author_reason'].strip() for r in detail['private_responses']):
            raise ValueError('source item/reason pairing absent')
        checked.append(source['private_review_acquisition_id'])
        target = {'items': 5, 'shared_options': 7, 'two_extra': True, 'option_at_most_once': True, 'heading_blank_items': [5], 'sentence_blank_items': [1, 2, 3, 4], 'complete_single_expository_text': True}
        if canonical(request['target_format']) != canonical(target):
            raise ValueError('five/seven/heading/sentence mode differs')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate) or author['specification_sha256'] != request['specification']['sha256'] or author['anchor_group_id'] != group['id'] or canonical(author['target_format']) != canonical(target):
            raise ValueError('author/source/target/current version differs')
        student = candidate.read_text().split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        if re.findall(r'\*\*\[([1-5])\]\*\*', student) != list('12345') or re.findall(r'^([A-G])\. ', student, re.M) != list('ABCDEFG'):
            raise ValueError('complete slots/options absent')
        if re.findall(r'^#### \*\*\[([1-5])\]\*\*$', student, re.M) != ['5'] or len(re.findall(r'^#### [^*].+$', student, re.M)) != 3:
            raise ValueError('heading blank or three visible headings absent')
        if '每个选项最多使用一次' not in student:
            raise ValueError('authored once instruction absent')
        vector = author['author_answer_vector']
        if len(vector) != 5 or len(set(vector)) != 5 or not set(vector) <= set('ABCDEFG') or author['whole_group_solved'] is not True:
            raise ValueError('complete source form author solution absent')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate', 'heading_and_sentence_functions_distinguished'}
        if not required <= set(request['author_output_required']) or not request['new_scenario'].strip() or not request['target_changes_and_justification']:
            raise ValueError('complete outputs/new scenario absent')
        if request['all_shared_material_required'] is not True or request['source_reference_list_exhaustive'] is not False or any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('material missing/exhaustive claim/source text embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False or (flag in author and author[flag] is not False):
                raise ValueError('unsupported admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from agreed scope')
    except (KeyError, ValueError, TypeError, OSError, StopIteration, IndexError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
