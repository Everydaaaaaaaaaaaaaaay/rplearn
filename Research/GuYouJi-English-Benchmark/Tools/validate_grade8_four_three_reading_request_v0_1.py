#!/usr/bin/env python3
"""Check four/three reading scope and actual component profiles; not difficulty."""
import argparse
import json
import re
from pathlib import Path
from profile_task_load import profile
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref


def check(request):
    checked = []
    try:
        if type(request['grade']) is not int or request['grade'] != 8:
            raise ValueError('grade must be integer8')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade8-v0.3.md' or request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade8-changjun2024-public-groups-v0.1.json':
            raise ValueError('wrong source/specification')
        file_ref(request['specification'])
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] != 'g8.changjun2024.readingC' or request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('wrong complete source/parent')
        if canonical(request['source_format']) != canonical({'items': 4, 'features': group['features']}) or canonical(request['positive_source_reference_numbers']) != canonical(group['question_numbers']):
            raise ValueError('source format/numbering differs')
        acqs = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent not PDF')
        checked.append(group['source_paper_acquisition_id'])
        private = cached(acqs[source['private_review_acquisition_id']])
        if digest(private) != source['private_review_sha256']:
            raise ValueError('private version differs')
        detail = next(g for g in json.loads(private.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != group['question_numbers'] or any(not r['author_reason'].strip() for r in detail['private_responses']):
            raise ValueError('source pairing/reasons absent')
        checked.append(source['private_review_acquisition_id'])
        target = {'items': 4, 'options_each': 3, 'complete_single_expository_text': True, 'body_paragraphs': 4, 'operations': ['paragraph1_example_mechanism', 'paragraph2_reason_information', 'paragraph3_it_reference', 'whole_passage_purpose'], 'source_photo_not_reused_or_required_for_new_questions': True}
        if canonical(request['target_format']) != canonical(target):
            raise ValueError('four/three/current operations or text input differs')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate) or author['specification_sha256'] != request['specification']['sha256'] or author['anchor_group_id'] != group['id'] or canonical(author['target_format']) != canonical(target):
            raise ValueError('author/current/source relations differ')
        student = candidate.read_text().split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        body = student.split('### Finding the Right Door', 1)[1].split('\n1.', 1)[0]
        paragraphs = [p.strip() for p in body.split('\n\n') if p.strip()]
        if len(paragraphs) != 4 or '**it**' not in paragraphs[2] or re.findall(r'^([1-4])\. ', student, re.M) != list('1234') or len(re.findall(r'^   [ABC]\. ', student, re.M)) != 12:
            raise ValueError('actual paragraph/pronoun/questions/options incomplete')
        prepared = cached(acqs[author['actual_task_load_input_acquisition_id']])
        record = json.loads(prepared.read_text())['records'][0]
        actual = profile(record)
        saved = json.loads(cached(acqs[author['actual_task_load_result_acquisition_id']]).read_text())['record']
        if actual != saved or actual != author['task_load'] or [r['text'] for r in record['components'] if r['role'] == 'passage'] != paragraphs:
            raise ValueError('component allocation/current body or measured report differs')
        expected_prompts = re.findall(r'^[1-4]\. (.+\?)$', student, re.M)
        if [r['text'] for r in record['components'] if r['role'] == 'prompt'] != expected_prompts or [r['text'] for r in record['components'] if r['role'] == 'option'] != re.findall(r'^   [ABC]\. (.+)$', student, re.M):
            raise ValueError('actual prompt/options not measured')
        checked += [author['actual_task_load_input_acquisition_id'], author['actual_task_load_result_acquisition_id']]
        if author['author_answer_vector'] != ['C', 'B', 'A', 'B'] or author['whole_group_solved'] is not True or not author['source_operator_changes_explicit'].strip():
            raise ValueError('complete author evidence/operator deltas absent')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate', 'paragraph_scope_and_pronoun_position_actual_checked', 'body_prompt_option_load_separate'}
        if not required <= set(request['author_output_required']) or not request['new_scenario'].strip() or not request['target_changes_and_justification']:
            raise ValueError('complete author outputs/context absent')
        if request['all_shared_material_required'] is not True or request['source_reference_list_exhaustive'] is not False or any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('material missing/exhaustive claim/source text embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False or (flag in author and author[flag] is not False):
                raise ValueError('unsupported admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from agreed scope')
    except (KeyError, ValueError, TypeError, OSError, StopIteration, IndexError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_load_to_difficulty_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_load_to_difficulty_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
