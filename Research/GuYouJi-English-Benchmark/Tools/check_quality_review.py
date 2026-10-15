#!/usr/bin/env python3
"""Reconcile every preview cell/task and image with pinned source-author metadata."""
import argparse
import base64
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, load_ref
from build_quality_review import FROZEN_PAGE


def extract(path):
    return json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>', path.read_text(), re.S)[1])


def check(page, matrix_path):
    data = extract(page); matrix = json.loads(matrix_path.read_text())
    previous = json.loads(re.search(r'<script id="showcase-data" type="application/json">(.*?)</script>', load_ref(FROZEN_PAGE).read_text(), re.S)[1])
    old = {g['id']: g for g in previous}; cases = []; groups = data['groups']; images = 0
    assert len(data['cells']) == len(matrix['cells']) == 144
    assert len({(c['grade'], c['family']) for c in data['cells']}) == 144
    assert sum(c['observed'] for c in data['cells']) == 70
    expected_preview_cells = sum(c['delivery_state'] in ['existing_complete_candidate_needs_review_UI','author_prototype_source_mode_pending'] for c in matrix['cells'])
    assert len(groups) == data['preview_cells'] == expected_preview_cells
    for cell, original in zip(data['cells'], matrix['cells']):
        assert (cell['grade'], cell['family'], cell['state']) == (original['grade'], original['family'], original['delivery_state'])
        if cell['groupId'] is None:
            assert original['delivery_state'] not in ['existing_complete_candidate_needs_review_UI','author_prototype_source_mode_pending']
            continue
        g = groups[cell['groupId']]
        meta = next(c for c in original['existing_authored_candidates'] if c['id'] == cell['groupId'])
        audit = json.loads(load_ref(meta['author_check']).read_text())
        assert g['grade'] == cell['grade'] == audit['grade']
        assert g['candidate'] == meta['candidate'] and len(g['questions']) == audit['questions']
        if g['id'] in old:
            assert g == old[g['id']], 'old complete payload changed'
        else:
            student = load_ref(meta['candidate']).read_text().split('\n## 学生题面\n')[1].split('\n## 作者',1)[0]
            assert '未评分参考示例' not in student and '原卷' not in student
            assert g['reviewText'] and g['reviewHtml']
        assert [q['number'] for q in g['questions']] == list(range(1, audit['questions']+1))
        if audit.get('options_each'):
            assert all(len(q['options']) == audit['options_each'] for q in g['questions'])
        for image in g.get('requiredPassageImages', []):
            raw = base64.b64decode(image['src'].split(',',1)[1], validate=True)
            assert hashlib.sha256(raw).hexdigest() == image['asset']['sha256']
            assert image['src'] in g['passageHtml']
            images += 1
        cases.append({'case': str(cell['grade'])+'/'+cell['family']+' complete pinned task', 'passed': True})
    assert {g['grade'] for g in groups.values()} == set(range(7,13))
    assert all(any(c['grade']==grade and c['family']=='application_writing' and c['groupId'] for c in data['cells']) for grade in range(7,13))
    return {'cases': cases, 'complete_task_controls': len(cases), 'preview_cells':len(groups),'source_positive_cells':70,
            'unknown_cells':74,'missing_authored_cells':sum(c['delivery_state']=='needs_complete_original_representative' for c in matrix['cells']),
            'simulated_source_only_cells_not_delivered':sum(c['delivery_state'].startswith('existing_simulated') for c in matrix['cells']),
            'prototype_source_mode_pending_cells':sum(c['delivery_state']=='author_prototype_source_mode_pending' for c in matrix['cells']),
            'response_positions':sum(len(g['questions']) for g in groups.values()),'writing_grade_coverage':list(range(7,13)),
            'required_embedded_passage_images_SHA_checked':images,'source_count_increment':0,
            'independent_teacher_student_commercial_or_production':False}


if __name__ == '__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--page',type=Path,required=True)
    p.add_argument('--matrix',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    args=p.parse_args();result=check(args.page,args.matrix)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='cases'},ensure_ascii=False))
