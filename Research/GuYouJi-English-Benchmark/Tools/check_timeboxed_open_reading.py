#!/usr/bin/env python3
"""Check complete open reading, mixed-task/table layout and response word policies."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE,evidence,load_ref
from quality_review_contract import response_markdown


def verify(r,a,t,s):
    if hashlib.sha256(t.encode()).hexdigest()!=r['candidate']['sha256']or a['candidate_sha256']!=r['candidate']['sha256']:raise ValueError('Candidate identity differs')
    if a['grade']!=s['shape']['grade']or a['grade']!=r['grade']or a['source_shape']!=s['shape']or a['family']!=s['shape']['family']:raise ValueError('Grade/full source configuration differs')
    qs=a['review_response_tasks'];n=s['shape']['responses'];student=t.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')[0];material=student.split('<!-- responses:start -->')[0];block=student.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if [q['number']for q in qs]!=list(range(1,n+1))or a['questions']!=n:raise ValueError('Full response count differs')
    if block!=response_markdown(qs)or hashlib.sha256(block.encode()).hexdigest()!=a['canonical_response_block_sha256']:raise ValueError('Printed/interactive response contract differs')
    limits=a['response_word_limits']
    if [q.get('maxWords')for q in qs]!=limits:raise ValueError('Per-response limits differ')
    source_limits=s['shape']['details'].get('per_response_word_limits')
    if source_limits and source_limits!=limits:raise ValueError('Source limits borrowed from another mode')
    for q in qs:
        refs=q.get('referenceAnswers',q.get('knownForms',[]))
        if not refs or not q['rationale']or q['options']:raise ValueError('Missing reference/boundary or invented choices')
        if q.get('maxWords') and any(len(v.split())>q['maxWords']for v in refs):raise ValueError('Reference exceeds explicit output length')
        if q.get('maxWords')==1 and any(len(v.split())!=1 for v in refs):raise ValueError('Exact one-word output required')
        if q.get('operation')=='one_word_contextual_synonym':
            target=re.search(r'“([^”]+)”',q['stem'])[1]
            if '**'+target+'**'not in material:raise ValueError('Missing visible bold target')
        if q.get('operation')in ['action_plus_reason','opinion_plus_reason','personal_opinion']and len(q.get('parts',[]))!=1:raise ValueError('One whole response split into extra tasks')
    if a['family']=='mixed_reading_response':
        if a.get('prompt_units')!=3 or limits!=[10,1,2,3,20]or [int(i)for i in re.findall(r'\((\d+)\) ________',material)]!=[2,3,4]:raise ValueError('Three tasks/five responses/table limits lost')
        if material.count('| Individual plan |')!=1 or '### 任务三'not in material:raise ValueError('Mixed task input incomplete')
    if a['family']=='open_table_completion':
        if a['table_response_distribution']!={'YES':2,'NO':3}or [int(i)for i in re.findall(r'\((\d+)\) ________',material)]!=list(range(1,6)):raise ValueError('YES/NO whole table missing')
        if not all(x in material for x in ['### The case for','### The case against','| YES |','| NO |']):raise ValueError('Position inputs missing')
    if a['source_frozen_input_state']is not s['necessary_input_complete']or any(a[k]is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):raise ValueError('Unearned source/validation claim')


def run(index):
    es={s['id']:s for s in evidence()};cases=[];total=0
    for r in json.loads(index.read_text())['candidates']:
        if r['family']not in ['open_reading_response','mixed_reading_response','open_table_completion']:continue
        a=json.loads(load_ref(r['author_check']).read_text());t=load_ref(r['candidate']).read_text();s=es[r['anchor_group_ids'][0]];verify(r,a,t,s);cases.append({'case':r['id']+' complete response/word/layout contract','passed':True});total+=a['questions']
        for label,m in [('last response removed',dict(a,review_response_tasks=a['review_response_tasks'][:-1])),('all same word limit',dict(a,response_word_limits=[1]*a['questions'])),('false independent review',dict(a,independent_review=True))]:
            try:verify(r,m,t,s)
            except ValueError as ex:cases.append({'case':r['id']+' rejects '+label,'passed':True,'reason':str(ex)})
            else:raise ValueError('Bad open contract admitted')
    return {'cases':cases,'controls':len(cases),'new_groups':len(cases)//4,'new_responses':total,'source_count_increment':0,'reference_sets_not_certified_exhaustive':True,'independent_student_commercial_or_production':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args();r=run(args.index);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='cases'}))
