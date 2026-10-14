#!/usr/bin/env python3
"""Check three prepared expansion input contracts; never evaluate an AI model.

The supported modes are deliberately limited to actual complete author examples.
Source bytes and author/version relations are local checks, not semantic gold.
"""
import argparse
import json
import re
from pathlib import Path
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref
from profile_task_load import count

MODES = {
    'grade7_six_cloze': {
        'grade': 7, 'group': 'g7.xicheng2025.clozeStory',
        'specification': 'FirstRelease/Specifications/grade7-v0.3.md',
        'catalogue': 'FirstRelease/Expansions/grade7-xicheng2025-public-groups-v0.1.json',
        'candidate': 'FirstRelease/Expansions/grade7-first-recording-six-cloze-v0.1.md',
        'target': {'items': 6, 'options_each': 3, 'response_unit': 'one_option_per_blank',
                   'complete_single_narrative': True, 'other_four_bank_is_separate_text': True},
        'positive_numbers': [27, 28, 29, 30, 31, 32],
        'excluded_explanation_numbers': [],
    },
    'grade8_local_concept': {
        'grade': 8, 'group': 'g8.fengtai2026.readingD',
        'specification': 'FirstRelease/Specifications/grade8-v0.5.md',
        'catalogue': 'FirstRelease/Expansions/grade8-fengtai2026-public-groups-v0.1.json',
        'candidate': 'FirstRelease/Expansions/grade8-maker-club-expectations-reading-v0.1.md',
        'target': {'items': 3, 'options_each': 4, 'body_paragraphs': 5,
                   'response_unit': 'one_option_per_question', 'local_definitions_are_fiction': True,
                   'specific_Monday_condition_not_source32_general_canhelp_scope': True,
                   'wordhead_level_is_not_context_level': True, 'topic_C2_not_word_grade': True},
        'positive_numbers': [31, 33],
        'excluded_explanation_numbers': [],
    },
    'grade8_sentence_translation': {
        'grade': 8, 'group': 'g8.bnu2026.translation',
        'specification': 'FirstRelease/Specifications/grade8-v0.5.md',
        'catalogue': 'FirstRelease/Expansions/grade8-bnu2026-public-groups-v0.1.json',
        'candidate': 'FirstRelease/Expansions/grade8-club-sentence-translation-v0.1.md',
        'target': {'items': 4, 'response_unit': 'one_complete_sentence_translation_per_prompt',
                   'hints_required_inflection_allowed': True, 'exact_string_gold': False,
                   'provisional_meaning_language_points_each': [1, 1],
                   'scoring_is_original_provisional_not_source_analytic_rubric': True},
        'positive_numbers': [48, 49, 50, 51],
        'excluded_explanation_numbers': [50],
    },
}


def check(request):
    checked = []
    try:
        mode = MODES[request['mode']]
        if type(request['grade']) is not int or request['grade'] != mode['grade']:
            raise ValueError('wrong integer grade')
        if request['specification']['path'] != mode['specification'] or request['source_catalogue']['path'] != mode['catalogue']:
            raise ValueError('wrong source/specification for this complete mode')
        file_ref(request['specification'])
        source = json.loads(file_ref(request['source_catalogue']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] != mode['group'] or request['source_parent_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('wrong complete group or parent family')
        if canonical(request['source_format']) != canonical({'items': len(group['question_numbers']), 'features': group['features']}):
            raise ValueError('source format is not the recorded complete group')
        if canonical(request['positive_source_reference_numbers']) != canonical(mode['positive_numbers']) or canonical(request['excluded_source_explanation_numbers']) != canonical(mode['excluded_explanation_numbers']):
            raise ValueError('positive references or excluded explanations differ')
        acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acquisitions[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('source parent is not actual PDF bytes')
        checked.append(group['source_paper_acquisition_id'])
        private = cached(acquisitions[source['private_review_acquisition_id']])
        if digest(private) != source['private_review_sha256']:
            raise ValueError('private source review version differs')
        detail = next(g for g in json.loads(private.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != group['question_numbers'] or any(not r['author_reason'].strip() for r in detail['private_responses']):
            raise ValueError('complete source reference/reason pairing missing')
        checked.append(source['private_review_acquisition_id'])
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if request['authored_example']['path'] != mode['candidate'] or author['candidate_path'] != mode['candidate'] or author['candidate_sha256'] != digest(candidate):
            raise ValueError('wrong complete author example or current version')
        if author['specification'] != request['specification'] or author['source_catalogue'] != request['source_catalogue'] or author['source_group_id'] != group['id'] or author['source_private_review_sha256'] != source['private_review_sha256']:
            raise ValueError('author/source/specification relationships differ')
        if canonical(request['target_contract']) != canonical(mode['target']):
            raise ValueError('target response unit, scoring or source-scope boundary differs')
        student = candidate.read_text().split('## 学生区\n\n', 1)[1].split('\n## 作者区', 1)[0]
        if request['mode'] == 'grade7_six_cloze':
            body = student.split('### The First Recording\n\n', 1)[1].split('\n1. A. ', 1)[0].strip()
            options = re.findall(r'^([1-6])\. A\. (.+?)　B\. (.+?)　C\. (.+?)$', student, re.M)
            if re.findall(r'___([1-6])___', body) != list('123456') or len(options) != 6 or author['questions'] != 6 or author['options_each'] != 3:
                raise ValueError('actual single six-blank/three-choice material incomplete')
            filled = body
            for (number, *words), item in zip(options, author['items']):
                if item['item'] != int(number) or words != item['all_three_options']:
                    raise ValueError('actual option rows differ from author evidence')
                filled = filled.replace('___' + number + '___', words['ABC'.index(item['author_letter'])])
            if filled != author['whole_group_refilled_text'] or count(filled) != author['task_load']['author_fully_refilled_body_not_student_input']:
                raise ValueError('whole group refill or output count differs')
        elif request['mode'] == 'grade8_local_concept':
            body = student.split('### Which Statement Are We Following?\n\n', 1)[1].split('\n1. ', 1)[0].strip()
            if len(body.split('\n\n')) != 5 or re.findall(r'^([1-3])\. ', student, re.M) != list('123') or len(re.findall(r'^[ABCD]\. ', student, re.M)) != 12:
                raise ValueError('actual five-paragraph three/four concept material incomplete')
            if author['complete_author_vector'] != ['C', 'D', 'B'] or 'Monday' not in body or 'both accepted a new return time' not in body:
                raise ValueError('current author/scope evidence missing')
            lexical = json.loads(file_ref(request['context_lexical_observations']).read_text())
            if lexical['candidate'] != request['authored_example'] or lexical['unlisted'] != 2:
                raise ValueError('lexical observations not bound to actual current context')
        else:
            prompts = re.findall(r'^([1-4])\. (.+?)（(.+?)）$', student, re.M)
            if len(prompts) != 4 or author['questions'] != 4 or author['source_analytic_rubric_supplied'] is not False:
                raise ValueError('actual complete translation/scoring boundary differs')
            for (number, chinese, hints), item in zip(prompts, author['items']):
                if int(number) != item['item'] or chinese != item['Chinese_meaning_prompt'] or hints.split(', ') != item['English_prompt_terms']:
                    raise ValueError('Chinese/hint inputs differ from author evidence')
            if len(author['synthetic_boundary_cases']) != 16 or any(r['actual_teacher_score'] is not None for r in author['synthetic_boundary_cases']):
                raise ValueError('original score examples are not the recorded author-only cases')
        required = {'complete_student_input', 'whole_task_author_solve_or_refill', 'all_choices_or_equivalent_response_review', 'source_to_target_changes', 'separate_input_output_load', 'actual_revision_if_changed', 'unknowns_and_independent_review_separate'}
        if not required <= set(request['author_output_required']) or not request['new_context_and_changes'].strip():
            raise ValueError('complete author output requirements or new context missing')
        for flag in ['independent_review','student_calibration','commercial_admission','production_admission','source_reference_set_exhaustive','source_original_republication_admitted','source_third_party_model_transmission_admitted','source_commercial_training_admitted']:
            if request[flag] is not False or flag in author and author[flag] is not False:
                raise ValueError('unsupported admission or exhaustive reference claim: ' + flag)
        if any(k in request for k in ['source_full_text','source_text_payload']) or canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only':True,'independent_character_opening_story':False}):
            raise ValueError('source body payload or display differs')
    except (KeyError, ValueError, TypeError, OSError, StopIteration, IndexError) as error:
        return {'metadata_and_local_material_bindings_valid':False,'errors':[str(error) or type(error).__name__],
                'cached_source_files_checked':checked,'model_called':False,'independent_English_student_or_rights_validation':False}
    return {'metadata_and_local_material_bindings_valid':True,'errors':[],
            'cached_source_files_checked':checked,'model_called':False,'independent_English_student_or_rights_validation':False}


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request',type=Path,required=True)
    args=parser.parse_args();result=check(json.loads(args.request.read_text()))
    print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if result['metadata_and_local_material_bindings_valid'] else 1)
