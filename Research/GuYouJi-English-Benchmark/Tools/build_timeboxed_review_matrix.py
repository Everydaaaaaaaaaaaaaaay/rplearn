#!/usr/bin/env python3
"""Plan one complete authored representative per observed grade/task family.

This is a delivery inventory, not a new source observation or a quality verdict.
"""
import argparse
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import load_ref

BASE = Path(__file__).resolve().parents[1]
LABELS = {
    'application_writing': '应用写作', 'choice_cloze': '单选完形',
    'context_word_completion': '语境词汇补全', 'dialogue_choice': '情境对话单选',
    'dialogue_matching': '共享候选对话补全', 'dialogue_open_completion': '开放对话补全',
    'grammar_choice_cloze': '语法选择语篇', 'mixed_reading_response': '混合阅读任务',
    'open_reading_response': '开放阅读表达', 'open_table_completion': '开放表格填空',
    'paragraph_heading_matching': '段落标题配对', 'passage_chinese_completion': '阅读后中文补全',
    'passage_form': '语篇语法/词形填空', 'phonetic_word_completion': '音标提示词汇补全',
    'picture_continuation': '看图续写', 'profile_matching': '人物需求/候选配对',
    'read_then_continue': '读后续写', 'reading_choice': '阅读单选', 'reading_tf': '阅读正误判断',
    'sentence_choice': '独立句单选', 'sentence_form': '句中语法/词形填空',
    'sentence_translation': '整句翻译', 'shared_bank': '共享词库填空',
    'shared_insertion': '共享句空衔接',
}


def ref(path):
    return {'path': str(path.relative_to(BASE)), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def build():
    appearance = BASE / 'FirstRelease/Sampling/grade-task-appearance-v0.1.json'
    source = json.loads(appearance.read_text())
    source_map = {s: (c['grade'], c['family']) for c in source['cells'] for s in c['source_group_ids']}
    selected = json.loads((BASE / 'FirstRelease/showcase-selection-v0.7.json').read_text())
    displayed = {r['id'] for r in selected['items']}
    indexes = [BASE / 'FirstRelease/review-index-v0.16.json',
               BASE / 'FirstRelease/Expansions/authored-candidate-index-v0.23.json',
               BASE / 'FirstRelease/open-language-supplement-candidates-v0.1.json']
    candidates = []
    for index in indexes:
        for row in json.loads(index.read_text())['candidates']:
            candidate = load_ref(row['candidate'])
            audit = json.loads(load_ref(row['author_check']).read_text())
            grade = row.get('grade', audit['grade'])
            if (audit['candidate_sha256'] != row['candidate']['sha256'] or audit['grade'] != grade or
                    row.get('questions', audit['questions']) != audit['questions']):
                raise ValueError('Candidate/audit digest, grade or response count differs')
            anchors = row.get('anchor_group_ids', audit.get('anchor_group_ids', [row.get('source_group_id')]))
            found = {source_map[s] for s in anchors if s in source_map}
            unpaired = {'grade10-project-advice-email': 'application_writing',
                        'grade10-exhibition-map-continuation': 'read_then_continue'}
            if not found and row['id'] in unpaired:
                load_ref(row['source_catalogue'])
                found = {(grade, unpaired[row['id']])}
                support = 'unpaired_source_form_and_rubric_reference_not_new_source_record'
            elif not found and row['id'] == 'grade8-relay-open-grammar-v0.1':
                load_ref(row['supplemental_reference'])
                if grade != 8 or anchors != ['g8.yogor2024.simulated.grammar']:
                    raise ValueError('Simulated supplement identity differs')
                found = {(8, 'passage_form')}
                support = 'simulated_source_form_reference_not_ordinary_school_replication'
            elif found:
                support = 'selected_source_group_form_reference'
            else:
                raise ValueError('Unmapped authored task: ' + row['id'])
            if len(found) != 1 or next(iter(found))[0] != grade:
                raise ValueError('Ambiguous/crossgrade authored mapping')
            if any(s and '.simulated.' in s for s in anchors):
                support = 'simulated_source_form_reference_not_ordinary_school_replication'
            family = next(iter(found))[1]
            candidates.append({'id': row['id'], 'grade': grade, 'family': family,
                               'questions': row.get('questions', audit['questions']),
                               'candidate': row['candidate'], 'author_check': row['author_check'],
                               'index': ref(index), 'source_group_ids': [s for s in anchors if s],
                               'source_form_support': support, 'in_previous_showcase': row['id'] in displayed,
                               'new_review_UI_verified': False})
    if len(candidates) != 53 or sum(c['questions'] for c in candidates) != 338:
        raise ValueError('Existing author inventory count differs')
    cells = []
    for original in source['cells']:
        cell = {k: original[k] for k in ['grade', 'family', 'observation_state', 'source_group_ids', 'input_states']}
        cell['label'] = LABELS[cell['family']]
        matched = [c for c in candidates if c['grade'] == cell['grade'] and c['family'] == cell['family']]
        matched.sort(key=lambda c: (not c['in_previous_showcase'], c['id']))
        cell['existing_authored_candidates'] = matched
        if original['observation_state'] != 'observed':
            if matched:
                raise ValueError('Author silently created an observed grade/family claim')
            cell['delivery_state'] = 'source_evidence_unknown_do_not_invent_grade_adaptation'
        elif not matched:
            cell['delivery_state'] = 'needs_complete_original_representative'
        elif all(c['source_form_support'].startswith('simulated_') for c in matched):
            cell['delivery_state'] = 'existing_simulated_anchor_candidate_needs_ordinary_source_form_review'
        else:
            cell['delivery_state'] = 'existing_complete_candidate_needs_review_UI'
        cell['selected_representative_id'] = matched[0]['id'] if matched else None
        cells.append(cell)
    states = {s: sum(c['delivery_state'] == s for c in cells) for s in sorted({c['delivery_state'] for c in cells})}
    return {'version': '0.1', 'scope': 'grades7_to12_timeboxed_quality_review_inventory',
            'source_appearance': ref(appearance), 'previous_showcase': ref(BASE / 'FirstRelease/showcase-selection-v0.7.json'),
            'existing_authored_groups': len(candidates), 'existing_authored_responses': sum(c['questions'] for c in candidates),
            'source_positive_cells': sum(c['observation_state'] == 'observed' for c in cells),
            'cell_delivery_states': states, 'cells': cells,
            'required_unit': 'one_complete_authored_task_group_per_observed_grade_family_not_one_subquestion',
            'one_representative_is_not_all_concrete_mode_combinations': True,
            'unknown_not_grade_absence': True, 'candidate_presence_not_quality_pass': True,
            'listening': {'included_in_written_matrix': False, 'current_complete_review_package_verified': False,
                          'delivery_rule': 'must_report_separately;no_text_only_task_claimed_as_complete_audio_task'},
            'independent_student_commercial_or_production_admission': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    result = build()
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Refuse changed frozen review inventory')
    args.output.write_text(payload)
    print(json.dumps({k: v for k, v in result.items() if k != 'cells'}, ensure_ascii=False))
