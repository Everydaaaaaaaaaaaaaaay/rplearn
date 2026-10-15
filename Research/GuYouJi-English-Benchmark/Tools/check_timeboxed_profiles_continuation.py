#!/usr/bin/env python3
"""Verify whole profile matching and one-task/two-paragraph continuation contracts."""
import argparse
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import BASE,evidence,load_ref
from quality_review_contract import response_markdown


def verify(r,a,t,s):
    if hashlib.sha256(t.encode()).hexdigest()!=r['candidate']['sha256']or a['candidate_sha256']!=r['candidate']['sha256']:raise ValueError('Candidate identity differs')
    if a['grade']!=r['grade']or a['grade']!=s['shape']['grade']or a['source_shape']!=s['shape']or a['family']!=s['shape']['family']:raise ValueError('Full source/grade differs')
    qs=a['review_response_tasks'];student=t.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')[0];printed=student.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if [q['number']for q in qs]!=list(range(1,s['shape']['responses']+1)):raise ValueError('Full response list differs')
    if printed!=response_markdown(qs)or hashlib.sha256(printed.encode()).hexdigest()!=a['canonical_response_block_sha256']:raise ValueError('Printed and interactive task differ')
    if a['family']=='profile_matching':
        count=s['shape']['details'].get('cards',s['shape']['details'].get('shared_options'))
        if len(a['shared_candidates'])!=count or a['left_items']!=s['shape']['responses']or a['reuse_rule']!='not_explicit':raise ValueError('Shared cards/left items/reuse differs')
        if any(q['options']!=a['shared_candidates']for q in qs):raise ValueError('Shared candidate card lost')
        for label,value in a['shared_candidates']:
            if student.split('<!-- responses:start -->')[0].count(label+'. '+value)!=1:raise ValueError('Shared card absent/duplicated')
        if any(not q['stem']or not q.get('rationale')or q['answer']not in [k for k,v in q['options']]for q in qs):raise ValueError('Missing profile/key/reason')
    else:
        if a['whole_task_responses']!=1 or len(qs)!=1 or len(qs[0]['parts'])!=2 or any(not p.get('opening')for p in qs[0]['parts']):raise ValueError('One continuation split or opening omitted')
        refs=a['continuation_reference_paragraphs'];counts=a['reference_word_counts']
        if [p['opening']for p in refs]!=[p['opening']for p in qs[0]['parts']]or any(not p['new_body']for p in refs):raise ValueError('Reference paragraphs do not bind openings')
        if qs[0]['referenceAnswers']!=[' '.join(p['opening']+' '+p['new_body']for p in refs)]:raise ValueError('Full reference flattened/truncated differently')
        if counts['given_openings']!=sum(len(p['opening'].split())for p in refs)or counts['new_body']!=sum(len(p['new_body'].split())for p in refs)or counts['including_openings']!=counts['given_openings']+counts['new_body']:raise ValueError('Reference word-count accounting differs')
        if a['source_given_opening_count_policy']!='not_explicit'or a['word_target']!=150 or a['target_relation']!='about':raise ValueError('Unobserved target policy')
    if a['source_frozen_input_state']is not s['necessary_input_complete']or any(a[k]is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):raise ValueError('Unearned validation/source claim')


def run(index):
    es={s['id']:s for s in evidence()};cases=[];total=0
    for r in json.loads(index.read_text())['candidates']:
        if r['family']not in ['profile_matching','read_then_continue']:continue
        a=json.loads(load_ref(r['author_check']).read_text());t=load_ref(r['candidate']).read_text();s=es[r['anchor_group_ids'][0]];verify(r,a,t,s);cases.append({'case':r['id']+' whole source/task contract','passed':True});total+=a['questions']
        for label,m in [('last response omitted',dict(a,review_response_tasks=a['review_response_tasks'][:-1])),('crossgrade',dict(a,grade=a['grade']+1)),('false independent review',dict(a,independent_review=True))]:
            try:verify(r,m,t,s)
            except ValueError as ex:cases.append({'case':r['id']+' rejects '+label,'passed':True,'reason':str(ex)})
            else:raise ValueError('Broken contract admitted')
    return {'cases':cases,'controls':len(cases),'new_groups':4,'new_responses':total,'continuations_whole_tasks':2,'source_count_increment':0,'independent_student_commercial_or_production':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args();r=run(args.index);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='cases'}))
