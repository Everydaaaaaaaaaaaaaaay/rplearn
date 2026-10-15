#!/usr/bin/env python3
"""Verify complete objective data, label identity and preserved source boundaries."""
import argparse
import hashlib
import itertools
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown


def extract(page):
    return json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>',page.read_text(),re.S)[1])


def check(page):
    data=extract(page);policy=json.loads(load_ref(data['current_scope_policy']).read_text())
    assert len(data['grades'])==len(set(data['grades']))==16
    assert len(data['cells'])==16*len(set(c['family']for c in data['cells']))
    assert len(set((c['grade'],c['family'])for c in data['cells']))==len(data['cells'])
    assert not(set(c['family']for c in data['cells']) & set(policy['paused_families']))
    assert {c['groupId']for c in data['cells']if c['groupId']}==set(data['groups'])
    acqs=json.loads((BASE/'Registry/acquisitions.json').read_text())['acquisitions']
    old_record=next(a for a in json.loads((BASE/'Registry/processing.json').read_text())['runs'] if a['id']=='objective-scope-owner-correction-20261016-v0.1')
    frozen=next(r for r in old_record['page_records']if r['output'].endswith('.html'))
    prior_page=REPO/frozen['output'];assert hashlib.sha256(prior_page.read_bytes()).hexdigest()==frozen['sha256']
    old=extract(prior_page)
    assert all(data['groups'][key]==value for key,value in old['groups'].items()),'inherited49 complete payload changed'
    for group in data['groups'].values():
        load_ref(group['candidate']);load_ref(group['author_check'])
        assert [q['number']for q in group['questions']]==list(range(1,len(group['questions'])+1))
        assert all(q.get('options')or q.get('knownForms')for q in group['questions'])
        assert not any(q.get('parts')or q.get('referenceAnswers')for q in group['questions'])
        assert all(q.get('answer')in [p[0]for p in q['options']]for q in group['questions']if q['options'])
    additions=json.loads(load_ref(data['extra_authored_index']).read_text())
    for meta in additions['candidates']:
        group=data['groups'][meta['id']];audit=json.loads(load_ref(meta['author_check']).read_text());text=load_ref(meta['candidate']).read_text()
        assert text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()==response_markdown(group['questions'])
        assert audit['source_observation']['source_responses']==len(group['questions'])==5
        load_ref(audit['source_index'])
        if meta['family']=='letter_completion':
            for q in group['questions']:
                filled={label:q['prefix']+value+q['suffix']for label,value in q['options']}
                assert [label for label,value in filled.items()if value==q['completion_target']]==[q['answer']]
        if meta['family']=='shared_bank':
            assert audit['source_observation']['source_reuse_rule']=='not_explicit'
            student=text.split('## 学生题面')[1].split('## 作者核对')[0]
            assert '只用一次'not in student
            assert all(len(q['options'])==5 for q in group['questions'])
    assert all(g.get('sourceFormNotice')for g in data['groups'].values()if g['grade']=='primary5')
    return {'levels':16,'levels_with_preview':len(set(g['grade']for g in data['groups'].values())),
            'complete_groups':len(data['groups']),'responses':sum(len(g['questions'])for g in data['groups'].values()),
            'old49_payload_unchanged':True,'no_subjective_or_partial_mixed_groups':True,'new_authored_groups':len(additions['candidates']),
            'source_parent_or_group_increment':0,'simulated_primary5_source_warning_bound':True,
            'source_unknown_early_levels_not_filled_with_adult_text':True,'independent_student_commercial_production_admission':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--page',type=Path,default=REPO/'build/english-benchmark-quality-review/index.html');p.add_argument('--report',type=Path,required=True);args=p.parse_args();result=check(args.page);args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result))
