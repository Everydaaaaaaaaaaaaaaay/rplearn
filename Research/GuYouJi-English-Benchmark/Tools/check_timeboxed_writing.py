#!/usr/bin/env python3
"""Check five complete authored writing packages; no semantic or teacher scoring."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref


def verify(row, audit, text, sources):
    source = sources[row['anchor_group_ids'][0]]
    if (row['grade'] != source['shape']['grade'] or audit['grade'] != row['grade'] or
            row['source_shape'] != source['shape'] or audit['source_shape'] != source['shape'] or
            row['family'] != 'application_writing' or audit['questions'] != 1):
        raise ValueError('Grade or complete source writing shape differs')
    if (source['shape']['responses'] != 1 or source['shape']['family'] != 'application_writing' or
            source['shape']['details']['word_target'] != audit['target_format']['body_words_about']):
        raise ValueError('Writing task unit/target differs')
    if audit['source_frozen_input_state'] is not source['necessary_input_complete'] or not audit['source_frozen_state_not_upgraded']:
        raise ValueError('Frozen source input state silently upgraded')
    if hashlib.sha256(text.encode()).hexdigest() != audit['candidate_sha256']:
        raise ValueError('Candidate bytes differ')
    if text.count('\n## 学生题面\n') != 1 or text.count('\n## 作者核对\n') != 1:
        raise ValueError('Explicit full student/author boundaries required')
    student, teacher = text.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')
    if any(v in student for v in ['未评分参考示例', '暂定评分说明', '流畅但任务错位', '原卷', '本原创']):
        raise ValueError('Private author/source notes leaked into student prompt')
    target = audit['target_format']
    for key in ['fixed_title', 'fixed_opening', 'fixed_closing']:
        if target[key] and target[key] not in student:
            raise ValueError('Given student text missing')
    if student.count('[在此写完整正文]') != 1:
        raise ValueError('One complete response field required')
    for key in ['author_positive_body', 'author_negative_body']:
        body = audit[key]
        if body not in teacher:
            raise ValueError('Full positive/negative author example missing')
        tokens = re.findall(r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*", body)
        if len(tokens) != audit[key + '_word_count']:
            raise ValueError('Body-word measurement differs')
    if (not audit['qualitative_scoring_guidance_only'] or audit['teacher_scored_examples'] or
            any(audit[k] is not False for k in ['independent_review', 'student_calibration', 'commercial_admission', 'production_admission', 'model_or_production_evaluation_called'])):
        raise ValueError('Unverified evaluation/score claim')
    if len(audit['author_positive_goal_support']) != 3 or not audit['negative_task_failure']:
        raise ValueError('Incomplete author goal/negative rationale')
    if audit.get('source_points_evidence'):
        marker = audit['source_points_evidence']; source_text = load_ref(audit['source_text']).read_text()
        segment = source_text[marker['start_offset']:marker['end_offset']]
        if segment != marker['text'] or hashlib.sha256(segment.encode()).hexdigest() != marker['sha256']:
            raise ValueError('Source score heading evidence differs')


def check():
    index = json.loads((BASE / 'FirstRelease/Timeboxed/authored-review-index-v0.1.json').read_text())
    sources = {r['id']: r for r in evidence()}; cases = []
    for row in index['candidates']:
        text = load_ref(row['candidate']).read_text(); audit = json.loads(load_ref(row['author_check']).read_text())
        verify(row, audit, text, sources)
        cases.append({'case': row['id']+' complete source form/student/author/count/provenance', 'passed': True})
        variants = []
        a = copy.deepcopy(audit); a['grade'] += 1; variants.append(('crossgrade audit', a))
        a = copy.deepcopy(audit); a['questions'] = 2; variants.append(('whole writing split into2tasks', a))
        a = copy.deepcopy(audit); a['teacher_scored_examples'] = True; variants.append(('unearned teacher score claim', a))
        a = copy.deepcopy(audit); a['author_positive_body_word_count'] += 7; variants.append(('fixed text/count silently combined', a))
        for label, a in variants:
            try:
                verify(row, a, text, sources)
            except ValueError as error:
                cases.append({'case': row['id']+' rejects '+label, 'passed': True, 'reason': str(error)})
            else:
                raise ValueError('Invalid writing package admitted: '+label)
    return {'cases': cases, 'controls': len(cases), 'positive': 5, 'rejection': 20,
            'new_authored_groups': 5, 'response_tasks': 5, 'new_source_groups': 0,
            'quality_inference_limit': 'mechanical input/provenance checks plus same-author qualitative review,not independent semantics/scoring/student calibration',
            'model_or_production_called': False}


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__); p.add_argument('--report', type=Path, required=True)
    args = p.parse_args(); result = check()
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}, ensure_ascii=False))
