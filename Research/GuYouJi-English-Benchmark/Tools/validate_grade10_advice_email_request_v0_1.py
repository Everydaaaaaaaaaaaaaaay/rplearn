#!/usr/bin/env python3
"""Check productive-task policies and local evidence; not numerical score validity."""
import argparse
import json
import re
from pathlib import Path
from profile_task_load import count
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref


def check(request):
    checked = []
    try:
        if type(request['grade']) is not int or request['grade'] != 10:
            raise ValueError('grade must be integer10')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade10-v0.3.md' or request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade10-wenzhou2025-public-groups-v0.1.json':
            raise ValueError('wrong source/specification')
        file_ref(request['specification'])
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        if type(request['source_task_number']) is not int or request['source_task_number'] != 66 or request['source_is_unpaired_productive_task_not_part_of45references'] is not True or request['source_paper_acquisition_id'] != source['source_paper_acquisition_id']:
            raise ValueError('wrong source writing identity or paired count claim')
        acqs = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[source['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent not PDF')
        checked.append(source['source_paper_acquisition_id'])
        if request['source_private_review_acquisition_id'] != source['private_review_acquisition_id']:
            raise ValueError('wrong private review')
        private = cached(acqs[source['private_review_acquisition_id']])
        if digest(private) != source['private_review_sha256']:
            raise ValueError('private version differs')
        writing = json.loads(private.read_text())['writing66']
        if canonical(request['source_format']) != canonical(writing) or writing['zero_score_policy_explicit_on_these_pages'] is not False or writing['scored_student_examples'] is not False:
            raise ValueError('source format/zero/scored evidence changed')
        checked.append(source['private_review_acquisition_id'])
        target = {'tasks': 1, 'genre': 'advice_email', 'content_goals': ['understanding_feeling', 'concrete_communication_advice', 'hope'], 'approximate_body_words': 80, 'given_salutation_and_signoff_excluded_by_authored_policy': True, 'maximum_points': 15, 'five_holistic_bands_high_to_low': [[13, 15], [10, 12], [7, 9], [4, 6], [1, 3]], 'band_first_then_within_band': True, 'independent_dimension_point_totals': False, 'zero_policy': 'authored_provisional_not_source_explicit', 'environment_invalid_distinct_from_language_zero': True}
        if canonical(request['target_format']) != canonical(target):
            raise ValueError('authored target/holistic/zero policy differs')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate) or author['specification_sha256'] != request['specification']['sha256'] or author['source_task_number'] != 66 or canonical(author['target_format']) != canonical(target) or canonical(author['source_format_observation']) != canonical(writing):
            raise ValueError('author/source/policy relation differs')
        text = candidate.read_text();student = text.split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        if 'Dear Alex,' not in student or 'Best regards,\nLi Hua' not in student or re.findall(r'^([123])\. ', student, re.M) != list('123'):
            raise ValueError('complete student goals/given format absent')
        author_area = text.split('## 作者区', 1)[1].split('## 暂定原创评分协议', 1)[0]
        examples = re.findall(r'Dear Alex,\n\n(.+?)\n\nBest regards,\nLi Hua', author_area, re.S)
        if len(examples) != 2 or len(author['authored_unscored_examples']) != 2 or author['two_examples_same_prompt_family_not_twoindependenttasks'] is not True:
            raise ValueError('complete unscored same-prompt author examples absent')
        import hashlib
        for body, evidence in zip(examples, author['authored_unscored_examples']):
            if hashlib.sha256(body.encode()).hexdigest() != evidence['body_sha256'] or count(body)['english_digit_tokens'] != evidence['body_tokens'] or evidence['teacher_score_observed'] is not False or evidence['numeric_score'] is not None:
                raise ValueError('unscored author body/signature/count/status differs')
            if body in student:
                raise ValueError('author example leaked into student prompt')
        if author['questions'] != 1 or author['explicit_source_zero_policy'] is not False or author['authored_zero_policy_provisional'] is not True or author['source_word_count_tolerance_verified'] is not False:
            raise ValueError('task/zero/tolerance provenance differs')
        for image in author['source_task_prompt_page_images']:
            path = cached(acqs[image['acquisition_id']])
            if image['PDF_page'] not in [8, 18, 19] or not path.name.endswith(f"inspection-{image['PDF_page']:02}.png"):
                raise ValueError('wrong prompt/rubric page image')
            checked.append(image['acquisition_id'])
        if [r['PDF_page'] for r in author['source_task_prompt_page_images']] != [8, 18, 19]:
            raise ValueError('complete re-read page set absent')
        required = {'complete_student_prompt_with_given_format', 'whole_task_goals_and_reasonable_alternatives', 'original_unscored_task_fulfilling_and_misaligned_examples', 'holistic_band_then_withinband_reasons_not_dimension_sum', 'source_vs_authored_policy_deltas_and_unknowns', 'actual_revision_evidence_if_changed', 'independent_scores_and_environment_validity_separate'}
        if not required <= set(request['author_output_required']) or not request['new_scenario'].strip() or not request['source_and_target_policy_deltas']:
            raise ValueError('author outputs/context/policy deltas absent')
        if any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('source fulltext embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold', 'source_scored_student_gold']:
            if request[flag] is not False or (flag in author and author[flag] is not False):
                raise ValueError('unsupported admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from agreed scope')
    except (KeyError, ValueError, TypeError, OSError, IndexError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'numerical_scoring_or_independent_English_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'numerical_scoring_or_independent_English_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
