#!/usr/bin/env python3
"""Validate seven actually prepared local authoring inputs, never run/evaluate a model.

The mode registry is bounded to exact sources, examples and versions. Whole-source
bytes, reference reasons and actual authored input are checked; source/reference
semantics, learner calibration and permissions still require separate evidence.
"""
import argparse
import itertools
import json
import re
from pathlib import Path
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref
from profile_task_load import count, profile

REGISTRY = 'FirstRelease/Expansions/PreparedSevenInputModes-v0.1.json'
BINDINGS = ['specification','source_catalogue','source_group_id','source_parent_acquisition_id',
            'source_key_acquisition_id','source_rationale_acquisition_id','source_format',
            'positive_source_reference_numbers','excluded_source_semantic_numbers',
            'excluded_source_explanation_numbers','authored_example','authored_example_check',
            'target_contract','authored_input_audit_acquisition_id','authored_input_record_id',
            'source_reference_set_exhaustive']
FALSE_FLAGS = ['independent_review','student_calibration','commercial_admission',
               'production_admission','source_original_republication_admitted',
               'source_third_party_model_transmission_admitted','source_commercial_training_admitted',
               'generation_run_occurred']
OUTPUT_REQUIRED = {'complete_student_input','whole_task_author_solve_or_refill',
                   'all_choices_or_equivalent_response_review','source_to_target_changes',
                   'separate_input_output_load','actual_revision_if_changed',
                   'unknowns_and_independent_review_separate'}


def check(request):
    checked = []
    try:
        allowed = set(BINDINGS + FALSE_FLAGS + ['version','mode_registry','mode','grade',
                          'new_context_and_changes','author_output_required','student_display','fact_strategy'])
        if set(request) != allowed:
            raise ValueError('missing or unsupported request fields; no source body payload admitted')
        if request['mode_registry']['path'] != REGISTRY:
            raise ValueError('unsupported mode registry')
        registry = json.loads(file_ref(request['mode_registry']).read_text())
        mode = next(row for row in registry['modes'] if row['mode'] == request['mode'])
        if type(request['grade']) is not int or request['grade'] != mode['grade']:
            raise ValueError('wrong integer grade for prepared mode')
        for key in BINDINGS:
            if canonical(request[key]) != canonical(mode[key]):
                raise ValueError('prepared source, example, scope or target differs: ' + key)
        file_ref(request['specification'])
        catalogue = json.loads(file_ref(request['source_catalogue']).read_text())
        group = next(g for g in catalogue['groups'] if g['id'] == request['source_group_id'])
        if group['grade'] != request['grade'] or not (group.get('complete_selected_group_reviewed') or group.get('complete_selected_group_visually_reviewed')):
            raise ValueError('grade or complete source group evidence missing')
        parent = group.get('source_paper_acquisition_id', group.get('acquisition_id'))
        key_parent = group.get('source_reference_key_acquisition_id', parent)
        if (request['source_parent_acquisition_id'],request['source_key_acquisition_id']) != (parent,key_parent):
            raise ValueError('wrong source parent/key family')
        expected_format = {'kind':group['kind'],'question_numbers':group['question_numbers'],'features':group['features']}
        if canonical(request['source_format']) != canonical(expected_format):
            raise ValueError('source group is truncated or its recorded format changed')
        acqs = {row['id']:row for row in json.loads((BASE/'Registry/acquisitions.json').read_text())['acquisitions']}
        for identity in dict.fromkeys([parent,key_parent]):
            p = cached(acqs[identity]);prefix = p.read_bytes()[:12]
            if not (prefix.startswith(b'%PDF-') or prefix[:4] == b'RIFF' and prefix[8:12] == b'WEBP'):
                raise ValueError('source parent bytes are not the reviewed PDF or WebP')
            checked.append(identity)
        detail = json.loads(cached(acqs[request['source_rationale_acquisition_id']]).read_text())
        checked.append(request['source_rationale_acquisition_id'])
        style = mode['source_rationale_style']
        if style == 'book_rationales':
            if detail['source_group_id'] != group['id'] or detail['parent_acquisition_id'] != parent:
                raise ValueError('book rationale source identity differs')
            rows = detail['rationales'];number_field, reason_field = 'n','basis'
        elif style == 'combined_reading_rationales':
            rows = next(g for g in detail['groups'] if g['id'] == group['id'])['author_reasons'];number_field,reason_field = 'n','basis'
        elif style == 'grade10_cloze_rationales':
            if group['id'] not in detail['source_groups']:
                raise ValueError('source cloze identity absent from review')
            rows = detail['grade10_author_source_rationale'];number_field,reason_field = 'n','basis'
        elif style == 'group_items':
            rows = next(g for g in detail['groups'] if g['group_id'] == group['id'])['items'];number_field,reason_field = 'source_number','author_analysis'
        elif style == 'group_private_responses':
            rows = next(g for g in detail['groups'] if g['id'] == group['id'])['private_responses'];number_field,reason_field = 'number','author_reason'
        else:
            raise ValueError('unsupported source rationale representation')
        if [r[number_field] for r in rows] != group['question_numbers'] or any(not isinstance(r[reason_field],str) or not r[reason_field].strip() for r in rows):
            raise ValueError('complete source reference/reason pairing missing')
        candidate = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_path'] != request['authored_example']['path'] or author['candidate_sha256'] != digest(candidate) or author['anchor_group_id'] != group['id'] or author['specification'] != request['specification'] or author['source_catalogue'] != request['source_catalogue']:
            raise ValueError('author example/source/specification version differs')
        if type(author['questions']) is not int or author['questions'] != request['target_contract']['items'] or author['grade'] != request['grade']:
            raise ValueError('actual author response unit/count differs')
        student = candidate.read_text().split('## 学生区',1)[1].split('## 作者区',1)[0]
        n = author['questions'];target = request['target_contract']
        if target['kind'] == 'reading_choice':
            if len(re.findall(r'^\d+\. ',student,re.M)) != n or len(re.findall(r'^   [A-D]\. ',student,re.M)) != n*4:
                raise ValueError('actual complete reading questions/options missing')
            data = json.loads(cached(acqs[request['authored_input_audit_acquisition_id']]).read_text())
            record = next(r for r in data['records'] if r['id'] == request['authored_input_record_id'])
            passages = [r for r in record['components'] if r['role']=='passage']
            if len(passages) != target['passage_components'] or any(r['text'] not in student.replace('**','') for r in passages) or profile(record) != author['task_load']:
                raise ValueError('current reading body/profile binding incomplete')
        elif target['kind'] == 'choice_cloze':
            body = student.split('<!-- passage:start -->')[1].split('<!-- passage:end -->')[0].strip()
            if re.findall(r'\((\d+)\) ____',body) != [str(i) for i in range(1,n+1)]:
                raise ValueError('actual complete cloze blank sequence differs')
            data = json.loads(cached(acqs[request['authored_input_audit_acquisition_id']]).read_text())
            record = next(r for r in data if r['id'] == request['authored_input_record_id'])
            actual = re.findall(r'^(\d+)\. A\. (.+?)　B\. (.+?)　C\. (.+?)　D\. (.+?)$',student,re.M)
            if len(actual)!=n or [list(r[1:]) for r in actual]!=record['options'] or body!='\n\n'.join(record['paras']):
                raise ValueError('actual cloze options/body differ from input audit')
            filled=body
            for i,(options,letter) in enumerate(zip(record['options'],author['author_answer_vector']),1):
                filled=filled.replace(f'({i}) ____',options['ABCD'.index(letter)])
            if filled!=record['filled'] or count(filled)!=author['task_load']['filled_author_reference']:
                raise ValueError('whole cloze reference refill differs')
        elif target['kind'] == 'passage_form':
            audit = json.loads(cached(acqs[request['authored_input_audit_acquisition_id']]).read_text())
            if audit != author['task_load']:
                raise ValueError('current grammar input/load audit differs')
            body=student.split('<!-- passage:start -->')[1].split('<!-- passage:end -->')[0].strip()
            if re.findall(r'\((\d+)\) ____',body)!=list(map(str,range(1,11))) or author['given_slots']!=target['given_slots'] or author['ungiven_oneword_slots']!=target['ungiven_oneword_slots'] or author['given_response_can_be_multiword'] is not True or author['author_key_exhaustive'] is not False:
                raise ValueError('single grammar response/form contract differs')
            for responses in itertools.product(*author['author_answer_vector']):
                filled=body
                for i,value in enumerate(responses,1):
                    if i in author['ungiven_oneword_slots'] and count(value)['english_digit_tokens']!=1:
                        raise ValueError('ungiven response violates one-word rule')
                    filled=re.sub(r'\('+str(i)+r'\) ____'+(r' \([^)]*\)' if i in author['given_slots'] else ''),value,filled)
                if '____' in filled or count(filled)!=author['task_load']['filled_reference']:
                    raise ValueError('whole grammar refill/body load differs')
        else:
            raise ValueError('unsupported current target kind')
        if not isinstance(request['new_context_and_changes'],str) or not request['new_context_and_changes'].strip() or not isinstance(request['author_output_required'],list) or any(not isinstance(x,str) for x in request['author_output_required']) or not OUTPUT_REQUIRED<=set(request['author_output_required']):
            raise ValueError('new context and full author outputs required')
        if canonical(request['student_display'])!=canonical({'avatar_next_to_instruction_only':True,'independent_character_opening_story':False}) or request['fact_strategy']!='fictional_context_not_source_claims_as_fact':
            raise ValueError('student display or factual strategy differs')
        for flag in FALSE_FLAGS:
            if request[flag] is not False or flag in author and author[flag] is not False:
                raise ValueError('unsupported admission or execution claim: '+flag)
        if request['source_reference_set_exhaustive'] is not False:
            raise ValueError('source reference set is not independently exhaustive')
    except (KeyError,ValueError,TypeError,OSError,StopIteration,IndexError,AttributeError) as exc:
        return {'metadata_and_local_material_bindings_valid':False,'errors':[str(exc) or type(exc).__name__],
                'cached_source_files_checked':checked,'model_called':False,'source_body_transmitted':False,
                'independent_English_student_or_rights_validation':False}
    return {'metadata_and_local_material_bindings_valid':True,'errors':[],
            'cached_source_files_checked':checked,'model_called':False,'source_body_transmitted':False,
            'independent_English_student_or_rights_validation':False}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--request',type=Path,required=True)
    args=parser.parse_args();result=check(json.loads(args.request.read_text()));print(json.dumps(result,ensure_ascii=False,indent=2))
    raise SystemExit(0 if result['metadata_and_local_material_bindings_valid'] else 1)
