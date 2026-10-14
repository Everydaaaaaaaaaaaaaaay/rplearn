#!/usr/bin/env python3
"""Check two authored grade8 request bindings; no English/model quality claim."""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path
from validate_extension_authoring_request_v0_1 import BASE, cached, canonical, digest, file_ref


def check(request):
    checked = []
    try:
        if type(request['grade']) is not int or request['grade'] != 8:
            raise ValueError('grade must be integer8')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade8-v0.3.md':
            raise ValueError('wrong specification')
        file_ref(request['specification'])
        if request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade8-changjun2024-public-groups-v0.1.json':
            raise ValueError('wrong source catalogue')
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] not in ['g8.changjun2024.readingA', 'g8.changjun2024.insertion']:
            raise ValueError('unsupported mode')
        if request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('wrong parent paper')
        expected = {'items': len(group['question_numbers']), 'features': group['features']}
        if canonical(request['source_format']) != canonical(expected) or canonical(request['positive_source_reference_numbers']) != canonical(group['question_numbers']):
            raise ValueError('source format or numbering changed')
        acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acquisitions[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent not PDF')
        checked.append(group['source_paper_acquisition_id'])
        detail_path = cached(acquisitions[source['private_review_acquisition_id']])
        if digest(detail_path) != source['private_review_sha256']:
            raise ValueError('source review version differs')
        detail = next(g for g in json.loads(detail_path.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != group['question_numbers'] or any(not r['author_reason'].strip() for r in detail['private_responses']):
            raise ValueError('source response/reason pairing absent')
        checked.append(source['private_review_acquisition_id'])
        candidate_path = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        if author['candidate_sha256'] != digest(candidate_path) or author['specification_sha256'] != request['specification']['sha256'] or author['anchor_group_id'] != group['id'] or canonical(author['target_format']) != canonical(request['target_format']):
            raise ValueError('author/spec/source/target relation differs')
        student = candidate_path.read_text().split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        target = request['target_format']
        if type(target['items']) is not int or target['items'] != len(group['question_numbers']) or author['questions'] != target['items'] or len(author['author_answer_vector']) != target['items'] or author['whole_group_solved'] is not True:
            raise ValueError('complete author response set absent')
        if group['kind'] == 'insertion':
            if canonical(target) != canonical({'items': 4, 'shared_options': 5, 'one_extra': True, 'option_at_most_once': True, 'complete_single_diary': True}):
                raise ValueError('unsupported four/five/atmostonce form')
            if re.findall(r'\*\*\[([1-4])\]\*\*', student) != list('1234') or re.findall(r'^([A-E])\. ', student, re.M) != list('ABCDE') or '每个选项最多使用一次' not in student:
                raise ValueError('student complete slots/options/once instruction absent')
            if len(set(author['author_answer_vector'])) != 4 or not set(author['author_answer_vector']) <= set('ABCDE'):
                raise ValueError('authored insertion reuse differs')
            if request['authored_once_rule_is_source_explicit'] is not False or author['source_option_once_explicit'] is not False:
                raise ValueError('authored once rule wrongly attributed to source')
        else:
            if canonical(target) != canonical({'items': 3, 'options_each': 3, 'categories': 6, 'population': 40, 'multiple_choices_allowed': True, 'denominator_each_category_all_participants': True, 'percent_sum_need_not100': True, 'complete_numbered_list_axis_and_labels': True}):
                raise ValueError('unsupported survey target or multiselect denominator changed')
            if re.findall(r'^([123])\. .*\?$', student, re.M) != list('123') or len(re.findall(r'^   [ABC]\. ', student, re.M)) != 9:
                raise ValueError('complete three/three questions absent')
            if len(re.findall(r'^\d\. ', student.split('![', 1)[0], re.M)) != 6:
                raise ValueError('numbered activity list absent')
            figure = file_ref(request['authored_figure'])
            if author['graph_asset'] != request['authored_figure'] or figure.name not in student:
                raise ValueError('figure absent or relation differs')
            xml = ET.fromstring(figure.read_text())
            desc = xml.find('{http://www.w3.org/2000/svg}desc').text
            visible = '\n'.join(t.text or '' for t in xml.findall('.//{http://www.w3.org/2000/svg}text'))
            pop = author['graph_population'];percent = author['graph_percentages'];counts = author['graph_counts']
            if type(pop) is not int or pop != target['population'] or len(percent) != 6 or len(counts) != 6:
                raise ValueError('graph population/category count differs')
            if any(type(v) is not int or not 0 <= v <= 100 for v in percent) or [Fraction(v * pop, 100) for v in percent] != counts or sum(counts) != author['category_choice_total'] or sum(percent) != author['graph_percent_sum']:
                raise ValueError('graph counts or multiselect total inconsistent')
            if any(str(v) + '%' not in desc or str(v) + '%' not in visible for v in percent):
                raise ValueError('accessible and visible percent labels differ')
            if re.search(r'\b(102|255|12)\b', desc) or '102' in visible:
                raise ValueError('current precomputed answer leaks in graph metadata')
            if not {'accessible_input_no_answer_leak', 'graph_units_denominator_and_date'} <= set(request['author_output_required']):
                raise ValueError('accessible/graph output controls absent')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate'}
        if not required <= set(request['author_output_required']) or not request['new_scenario'].strip() or not request['target_changes_and_justification']:
            raise ValueError('complete author outputs/new context absent')
        if request['all_shared_material_required'] is not True or request['source_reference_list_exhaustive'] is not False:
            raise ValueError('missing material or exhaustive reference claim')
        if any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('source text payload embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False or (flag in author and author[flag] is not False):
                raise ValueError('unsupported admission: ' + flag)
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from agreed instruction')
    except (KeyError, ValueError, TypeError, OSError, StopIteration, IndexError, AttributeError, ET.ParseError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
