#!/usr/bin/env python3
"""Verify complete dialogue/passage input contracts; not semantic or student admission."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from quality_review_contract import response_markdown


def verify(row, a, text, s):
    if a['candidate_sha256'] != row['candidate']['sha256'] or hashlib.sha256(text.encode()).hexdigest()!=a['candidate_sha256']:
        raise ValueError('Candidate identity differs')
    if a['grade']!=row['grade'] or a['grade']!=s['shape']['grade'] or a['family']!=s['shape']['family'] or a['source_shape']!=s['shape'] or row['source_shape']!=s['shape']:
        raise ValueError('Grade/family/exact source configuration differs')
    qs=a['review_response_tasks'];n=s['shape']['responses']
    if a['questions']!=n or [q['number'] for q in qs]!=list(range(1,n+1)):
        raise ValueError('Incomplete response sequence')
    student=text.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')[0];material=student.split('<!-- responses:start -->')[0]
    block=student.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if block!=response_markdown(qs) or hashlib.sha256(block.encode()).hexdigest()!=a['canonical_response_block_sha256']:
        raise ValueError('Printed and interactive response contracts differ')
    if a['family']!='reading_tf' and [int(i) for i in re.findall(r'\((\d+)\) ________',material)]!=list(range(1,n+1)):
        raise ValueError('Passage missing numbered slot')
    if a.get('shared_candidates'):
        if len(a['shared_candidates'])!=s['shape']['details']['shared_options'] or a['reuse_rule']!='not_explicit':
            raise ValueError('Shared set or reuse policy differs')
        if any(q['options']!=a['shared_candidates'] for q in qs):
            raise ValueError('Interactive shared set differs')
        for label,value in a['shared_candidates']:
            if material.count(label+'. '+value)!=1:raise ValueError('Printed shared input duplicated or absent')
    elif a['options_each']:
        if any(len(q['options'])!=a['options_each'] for q in qs):raise ValueError('Per-response candidates missing')
    else:
        if a['family']!='dialogue_open_completion' or any(q['options'] or q.get('maxWords')!=1 or not q.get('knownForms') for q in qs):
            raise ValueError('Open one-word policy differs')
        if any(len(v.split())!=1 for q in qs for v in q['knownForms']):raise ValueError('Multiword reference violates one-word rule')
    for q in qs:
        if not q['rationale']:raise ValueError('Missing rationale')
        if q['options'] and q.get('answer')not in [k for k,v in q['options']]:raise ValueError('Missing author key')
        if q.get('author_option_checks'):
            c=q['author_option_checks']
            if [x['label'] for x in c]!=[k for k,v in q['options']] or [x['label'] for x in c if x['valid']]!=[q['answer']] or any(not x['reason'] for x in c):raise ValueError('Option review incomplete')
    if a['family']=='reading_tf' and any(q['options']!=[['A','正确'],['B','错误']] for q in qs):raise ValueError('Invented extra judgment option')
    if a['source_frozen_input_state']is not s['necessary_input_complete'] or not a['source_frozen_state_not_upgraded']:raise ValueError('Source state upgraded')
    if any(a[k]is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):raise ValueError('Unearned admission')


def run(index):
    es={s['id']:s for s in evidence()};cases=[];total=0
    for r in json.loads(index.read_text())['candidates']:
        if r['family']not in ['dialogue_choice','dialogue_matching','dialogue_open_completion','grammar_choice_cloze','reading_tf']:continue
        a=json.loads(load_ref(r['author_check']).read_text());t=load_ref(r['candidate']).read_text();s=es[r['anchor_group_ids'][0]]
        sr=a['source_reference'];st=load_ref(sr['source_text']).read_text();raw=st[sr['start_offset']:sr['end_offset']]
        assert hashlib.sha256(raw.encode()).hexdigest()==sr['material_sha256'];load_ref(sr['source_view_manifest'])
        verify(r,a,t,s);cases.append({'case':r['id']+' complete contract','passed':True});total+=a['questions']
        bad=copy.deepcopy(a);bad['review_response_tasks'].pop()
        for name,m in [('last task removed',bad),('crossgrade',dict(a,grade=a['grade']+1)),('false production admission',dict(a,production_admission=True))]:
            try:verify(r,m,t,s)
            except ValueError as ex:cases.append({'case':r['id']+' rejects '+name,'passed':True,'reason':str(ex)})
            else:raise ValueError('Invalid task admitted '+name)
    return {'cases':cases,'controls':len(cases),'new_groups':len(cases)//4,'new_responses':total,'source_count_increment':0,'independent_semantic_student_or_production_validation':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    args=p.parse_args();r=run(args.index);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='cases'}))
