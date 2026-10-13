#!/usr/bin/env python3
"""Bind two authored grade7 modes to current source/spec; not a semantic eval."""
import argparse
import json
import re
from pathlib import Path
from validate_extension_authoring_request_v0_1 import cached, canonical, digest, file_ref

BASE = Path(__file__).resolve().parents[1]


def check(request):
    checked = []
    try:
        if request['specification']['path'] != 'FirstRelease/Specifications/grade7-v0.3.md':
            raise ValueError('wrong grade7 specification')
        file_ref(request['specification'])
        if request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade7-xicheng2025-public-groups-v0.1.json':
            raise ValueError('unsupported source catalogue')
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if canonical(request['grade']) != canonical(7) or group['grade'] != 7:
            raise ValueError('wrong grade or scalar type')
        if request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('wrong parent paper/key bundle')
        if canonical(request['source_format']) != canonical({'items': len(group['question_numbers']), 'features': group['features']}):
            raise ValueError('source mode/once/form-change declarations differ')
        acqs = {a['id']: a for a in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent actual bytes not PDF')
        checked.append(group['source_paper_acquisition_id'])
        detail_path = cached(acqs[source['private_review_acquisition_id']])
        if digest(detail_path) != source['private_review_sha256']:
            raise ValueError('private review version differs')
        detail = next(g for g in json.loads(detail_path.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != group['question_numbers'] or any(not r['author_reason'] for r in detail['private_responses']):
            raise ValueError('source response pairing or author reasons missing')
        checked.append(source['private_review_acquisition_id'])
        allowed = {
            'g7.xicheng2025.matchingA': {'items': 3, 'activity_cards': 4, 'one_extra_option': True, 'option_reuse_rule': 'at_most_once', 'complete_text_cards_and_profiles': True},
            'g7.xicheng2025.clozeBank': {'items': 4, 'bank_entries': 4, 'entry_once': True, 'form_change': False, 'complete_single_prose': True},
        }
        if canonical(request['target_format']) != canonical(allowed[group['id']]):
            raise ValueError('unsupported complete authored target')
        if request['authored_once_rule_is_source_explicit'] is not False:
            raise ValueError('original once rule falsely attributed to source')
        if canonical(request['positive_source_reference_numbers']) != canonical(group['question_numbers']):
            raise ValueError('selected source numbers incomplete or wrong group')
        if request['source_reference_list_exhaustive'] is not False or request['all_shared_material_required'] is not True:
            raise ValueError('reference exhaustiveness or incomplete material')
        if not isinstance(request['new_scenario'], str) or not request['new_scenario'].strip():
            raise ValueError('new scenario required')
        changes = request['target_changes_and_justification']
        if not isinstance(changes, list) or not changes or any(not isinstance(s, str) or not s.strip() for s in changes):
            raise ValueError('target changes required')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate'}
        output = request['author_output_required']
        if not isinstance(output, list) or any(not isinstance(s, str) for s in output) or not required.issubset(output):
            raise ValueError('author output requirements missing')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate) or author['anchor_group_id'] != group['id'] or author['specification_sha256'] != request['specification']['sha256']:
            raise ValueError('authored example/spec/source relation differs')
        text = candidate.read_text()
        if '## 学生区' not in text or '## 作者区' not in text:
            raise ValueError('student/author sections missing')
        student = text.split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        if group['id'].endswith('matchingA'):
            if re.findall(r'^### ([ABCD]) ·', student, re.M) != list('ABCD') or re.findall(r'^([123])\. ', student, re.M) != list('123'):
                raise ValueError('four cards/three profiles absent')
            if len(author['author_answer_vector']) != 3 or len(set(author['author_answer_vector'])) != 3 or set(author['author_answer_vector']) | {author['unused_option']} != set('ABCD'):
                raise ValueError('matching vector/unused option inconsistent')
            if author['all_twelve_pairs_same_author_reviewed'] is not True:
                raise ValueError('whole matching alternatives not reviewed')
        else:
            if re.findall(r'\(([1-4])\) ___', student) != list('1234') or sorted(author['author_answer_vector']) != sorted(author['wordbank_entries']):
                raise ValueError('four blank/bank-use allocation inconsistent')
            if author['entry_once'] is not True or author['form_change'] is not False or author['all_four_same_author_refilled'] is not True:
                raise ValueError('authored bank or refill constraint missing')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission']:
            if author[flag] is not False or request[flag] is not False:
                raise ValueError('unsupported author/request admission: ' + flag)
        if any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('source body embedded in metadata request')
        for flag in ['original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False:
                raise ValueError('unsupported source admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display conflicts with requested design')
        if request['fact_strategy'] != 'fictional_context_and_numbers_not_source_claims_as_fact':
            raise ValueError('factual strategy differs')
    except (KeyError, ValueError, OSError, TypeError, StopIteration) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
