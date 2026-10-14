#!/usr/bin/env python3
"""Check mixed-slot source bindings and saved instruction transition; not semantics."""
import argparse
import json
import re
from pathlib import Path
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref


def check(request):
    checked = []
    try:
        if type(request['grade']) is not int or request['grade'] != 11:
            raise ValueError('grade must be integer11')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade11-v0.3.md' or request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade11-spring2024-public-groups-v0.1.json' or request['source_slot_annotation']['path'] != 'FirstRelease/Expansions/grade11-insertion-slot-functions-v0.1.json':
            raise ValueError('wrong source/spec/function annotation')
        file_ref(request['specification'])
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        note = json.loads(file_ref(request['source_slot_annotation']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] != 'g11.spring2024.insertionE' or note['source_group_id'] != group['id'] or request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('wrong complete source/parent')
        if canonical(request['source_format']) != canonical({'items': 5, 'features': group['features']}) or canonical(request['all_source_reference_numbers']) != canonical(group['question_numbers']):
            raise ValueError('source format/numbering changed')
        if canonical(request['source_reference_exclusions']) != canonical(note['positive_source_reference_exclusion_provisional_for_next_request']) or canonical(request['positive_source_reference_numbers']) != canonical([36, 37, 38, 40]):
            raise ValueError('unresolved source39 promoted as positive semantic gold')
        if request['source_once_rule_explicit'] is not False or request['authored_once_rule_is_source_explicit'] is not False or note['all_seven_options_must_be_full_independent_sentences'] is not False:
            raise ValueError('once/full-sentence source rule invented')
        if canonical(request['source_function_number_to_target_item']) != canonical({'36': 1, '37': 2, '38': 3, '39': 4, '40': 5}):
            raise ValueError('source-to-target function mapping changed')
        acqs = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent not PDF')
        checked.append(group['source_paper_acquisition_id'])
        private = cached(acqs[source['private_review_acquisition_id']])
        if digest(private) != source['private_review_sha256']:
            raise ValueError('source review changed')
        detail = next(g for g in json.loads(private.read_text())['groups'] if g['group_id'] == group['id'])
        if [r['source_number'] for r in detail['items']] != group['question_numbers'] or any(not r['author_analysis'].strip() for r in detail['items']):
            raise ValueError('source item/reason pairing absent')
        checked.append(source['private_review_acquisition_id'])
        image = cached(acqs[note['re_read_page_image_acquisition_id']])
        if digest(image) != note['page_image_sha256'] or note['heading_source_numbers'] != [37] or note['conditional_fragment_source_numbers'] != [39]:
            raise ValueError('source page/layout annotation differs')
        checked.append(note['re_read_page_image_acquisition_id'])
        target = {'items': 5, 'shared_options': 7, 'two_extra': True, 'option_at_most_once': True, 'heading_blank_items': [2], 'opening_coordinated_clause_items': [1], 'conditional_clause_items': [4], 'complete_sentence_items': [3, 5], 'function_hints_in_student_instruction': False, 'complete_single_guidance_text': True}
        if canonical(request['target_format']) != canonical(target):
            raise ValueError('mixed heading/clause/sentence target differs')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate) or author['specification_sha256'] != request['specification']['sha256'] or author['anchor_group_id'] != group['id'] or canonical(author['target_format']) != canonical(target) or author['source_slot_annotation'] != request['source_slot_annotation']:
            raise ValueError('author/current/source relations differ')
        prior = file_ref(author['prior_candidate'])
        audit_path = cached(author['actual_revision_audit_cache_ref']);audit = json.loads(audit_path.read_text())
        if audit['prior_sha256'] != digest(prior) or audit['current_sha256'] != digest(candidate) or author['actual_saved_transition_rounds'] != 1 or audit['actual_saved_transition_rounds'] != 1:
            raise ValueError('actual saved transition evidence differs')
        def student(path):
            return path.read_text().split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        current = student(candidate);old = student(prior);title = '### Choosing a Question You Can Investigate'
        if current.split(title, 1)[1] != old.split(title, 1)[1] or audit['prior_student_instruction'] not in old or audit['current_student_instruction'] not in current or '第2空为小标题' in current:
            raise ValueError('current instructions/body transition differs')
        if re.findall(r'\*\*\[([1-5])\]\*\*', current) != list('12345') or re.findall(r'^([A-G])\. ', current, re.M) != list('ABCDEFG') or re.findall(r'^#### \*\*\[([1-5])\]\*\*$', current, re.M) != ['2']:
            raise ValueError('complete slots/options/heading absent')
        if '**[1]**, so' not in current or '**[4]**, ask' not in current or '**[3]**.' not in current or '**[5]**.' not in current or '每项最多使用一次' not in current:
            raise ValueError('material-supplied punctuation or once instruction absent')
        if author['author_answer_vector'] != ['B', 'F', 'A', 'G', 'D'] or author['whole_group_solved'] is not True or author['source39_not_positive_semantic_gold'] is not True:
            raise ValueError('current author vector/risk evidence differs')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate', 'heading_clause_sentence_and_supplied_punctuation_distinguished', 'quarantined_source_semantics_not_positive_gold'}
        if not required <= set(request['author_output_required']) or not request['new_scenario'].strip() or not request['target_changes_and_justification']:
            raise ValueError('complete author outputs/context absent')
        if request['all_shared_material_required'] is not True or request['source_reference_list_exhaustive'] is not False or any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('missing material/exhaustive claim/source body embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False or (flag in author and author[flag] is not False):
                raise ValueError('unsupported admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from agreed scope')
    except (KeyError, ValueError, TypeError, OSError, StopIteration, IndexError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_student_or_instruction_difficulty_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_student_or_instruction_difficulty_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
