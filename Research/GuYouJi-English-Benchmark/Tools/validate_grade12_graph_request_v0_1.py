#!/usr/bin/env python3
"""Check the currently authored grade12 chart request; not generated English."""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from decimal import Decimal
from pathlib import Path
from validate_extension_authoring_request_v0_1 import cached, canonical, digest, file_ref

BASE = Path(__file__).resolve().parents[1]


def check(request):
    checked = []
    try:
        if canonical(request['grade']) != canonical(12):
            raise ValueError('wrong grade or scalar type')
        if request['specification']['path'] != 'FirstRelease/Specifications/grade12-v0.3.md':
            raise ValueError('wrong specification')
        file_ref(request['specification'])
        if request['source_extension_ref']['path'] != 'FirstRelease/Expansions/grade12-national2025-public-groups-v0.1.json':
            raise ValueError('wrong source catalogue')
        source = json.loads(file_ref(request['source_extension_ref']).read_text())
        group = next(g for g in source['groups'] if g['id'] == request['source_group_id'])
        if group['id'] != 'g12.national2025.readingA' or request['source_paper_acquisition_id'] != group['source_paper_acquisition_id']:
            raise ValueError('unsupported source group or parent')
        if canonical(request['source_format']) != canonical({'items': 3, 'features': group['features']}) or canonical(request['positive_source_reference_numbers']) != canonical([1, 2, 3]):
            raise ValueError('source format or actual printed numbering differs')
        acqs = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
        parent = cached(acqs[group['source_paper_acquisition_id']])
        if parent.read_bytes()[:5] != b'%PDF-':
            raise ValueError('parent bytes not PDF')
        checked.append(group['source_paper_acquisition_id'])
        detail_path = cached(acqs[source['private_review_acquisition_id']])
        if digest(detail_path) != source['private_review_sha256']:
            raise ValueError('source author review version differs')
        detail = next(g for g in json.loads(detail_path.read_text())['groups'] if g['id'] == group['id'])
        if [r['number'] for r in detail['private_responses']] != [1, 2, 3] or any(not r['author_reason'] for r in detail['private_responses']):
            raise ValueError('complete source pairing/reasons absent')
        checked.append(source['private_review_acquisition_id'])
        target = {'items': 3, 'options_each': 4, 'solution_cards': 5, 'graph_categories': 6, 'complete_graph_cards_and_final_quote': True, 'equivalent_accessible_values_without_precomputed_answer': True}
        if canonical(request['target_format']) != canonical(target):
            raise ValueError('incomplete graph/cards/quote target')
        candidate_path = file_ref(request['authored_example'])
        author = json.loads(file_ref(request['authored_example_check']).read_text())
        figure_path = file_ref(request['authored_figure'])
        if author['candidate_sha256'] != digest(candidate_path) or author['specification_sha256'] != request['specification']['sha256'] or author['anchor_group_id'] != group['id'] or canonical(author['graph_asset']['path']) != canonical(request['authored_figure']['path']) or author['graph_asset']['sha256'] != digest(figure_path):
            raise ValueError('author/current figure/spec/source relation differs')
        text = candidate_path.read_text()
        student = text.split('## 学生区', 1)[1].split('## 作者区', 1)[0]
        if len(re.findall(r'^#### ', student, re.M)) != 5 or re.findall(r'^([123])\. ', student, re.M) != list('123') or len(re.findall(r'^   [ABCD]\. ', student, re.M)) != 12:
            raise ValueError('current example cards/items/options incomplete')
        if Path(author['graph_asset']['path']).name not in student:
            raise ValueError('current figure absent from student material')
        svg = ET.fromstring(figure_path.read_text())
        desc = svg.find('{http://www.w3.org/2000/svg}desc').text
        # Actual discovered v0.1 defect: only accessible metadata exposed the sum.
        if '54.5' in desc or any('54.5' in (t.text or '') for t in svg.findall('.//{http://www.w3.org/2000/svg}text')):
            raise ValueError('precomputed answer leaked outside choices')
        shares = [Decimal(x) for x in author['graph_shares']]
        if len(shares) != 6 or sum(shares) != Decimal('100.0') or sum(shares[:2]) != Decimal('54.5'):
            raise ValueError('current fictional graph allocation differs')
        if author['all_three_same_author_solved'] is not True or author['author_answer_vector'] != ['C', 'C', 'B'] or author['actual_saved_transition_rounds'] != 1:
            raise ValueError('current complete author/revision evidence differs')
        if request['source_original_official_number_mapping_verified'] is not False or request['source_reference_list_exhaustive'] is not False or request['all_shared_material_required'] is not True:
            raise ValueError('original identity/exhaustiveness or missing material claim')
        if not isinstance(request['new_scenario'], str) or not request['new_scenario'].strip() or not isinstance(request['target_changes_and_justification'], list) or not request['target_changes_and_justification']:
            raise ValueError('new context/changes absent')
        required = {'complete_student_material', 'per_item_evidence_and_alternatives', 'whole_group_solve_or_refill', 'actual_revision_evidence_if_changed', 'independent_unknowns_separate', 'accessible_input_no_answer_leak', 'graph_units_denominator_and_date'}
        if not isinstance(request['author_output_required'], list) or not required.issubset(request['author_output_required']):
            raise ValueError('author outputs absent')
        if any(k in request for k in ['source_full_text', 'source_text_payload']):
            raise ValueError('source body embedded')
        for flag in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'original_source_republication_admitted', 'commercial_training_admitted', 'third_party_source_transmission_admitted', 'source_factual_gold']:
            if request[flag] is not False:
                raise ValueError('unsupported admission: ' + flag)
        if request['fact_strategy'] != 'fictional_context_and_numbers_not_source_claims_as_fact':
            raise ValueError('source facts silently certified')
        if canonical(request['student_display']) != canonical({'avatar_next_to_instruction_only': True, 'independent_character_opening_story': False, 'correct_title_leaked': False}):
            raise ValueError('display differs from requested scope')
    except (KeyError, ValueError, OSError, TypeError, StopIteration, IndexError, AttributeError, ET.ParseError) as exc:
        return {'metadata_and_source_bindings_valid': False, 'errors': [str(exc) or type(exc).__name__], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}
    return {'metadata_and_source_bindings_valid': True, 'errors': [], 'actual_cached_source_files_checked': checked, 'model_called': False, 'independent_English_or_student_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--request', type=Path, required=True)
    args = parser.parse_args()
    result = check(json.loads(args.request.read_text()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['metadata_and_source_bindings_valid'] else 1)
