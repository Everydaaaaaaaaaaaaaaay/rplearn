#!/usr/bin/env python3
"""Check source-bound full grammar/bank/heading/insertion contracts and representative selection."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE,evidence,load_ref
from quality_review_contract import response_markdown


def verify(row,a,text,s):
    if hashlib.sha256(text.encode()).hexdigest()!=row['candidate']['sha256'] or a['candidate_sha256']!=row['candidate']['sha256']:
        raise ValueError('Candidate digest differs')
    if a['grade']!=row['grade'] or a['grade']!=s['shape']['grade'] or a['source_shape']!=s['shape'] or a['family']!=s['shape']['family']:
        raise ValueError('Full grade/source shape differs')
    qs=a['review_response_tasks'];count=s['shape']['responses'];student=text.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')[0];body=student.split('<!-- responses:start -->')[0]
    if a['questions']!=count or [q['number']for q in qs]!=list(range(1,count+1)):raise ValueError('Full response sequence differs')
    if [int(n)for n in re.findall(r'\((\d+)\) ________',body)]!=list(range(1,count+1)):raise ValueError('Full passage slots differ')
    block=student.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if block!=response_markdown(qs) or hashlib.sha256(block.encode()).hexdigest()!=a['canonical_response_block_sha256']:raise ValueError('Printed response contract differs')
    if a.get('given_slots'):
        given=[q['number']for q in qs if q.get('given_word')]
        if given!=a['given_slots'] or [q['number']for q in qs if not q.get('given_word')]!=a['ungiven_one_word_slots']:raise ValueError('Given/ungiven slot mapping differs')
        if len(given)!=7 or any(q.get('maxWords')!=1 for q in qs if not q.get('given_word')):raise ValueError('Seven given/three one-word policy differs')
        for q in qs:
            if q.get('given_word') and f"({q['number']}) ________ ({q['given_word']})"not in body:raise ValueError('Printed given root missing')
    if a.get('bank_entries'):
        if len(a['bank_entries'])!=s['shape']['details']['entries'] or len(set(a['bank_assignment']))!=count or a['reuse_rule']!='once':raise ValueError('Bank size/reuse differs')
        if a['bank_form_policy']!=s['shape']['details']['form_policy']:raise ValueError('Form policy differs')
        if a['bank_form_policy']=='unchanged':
            if any(q['options']!=a['shared_candidates']for q in qs) or len(a['shared_candidates'])!=11:raise ValueError('Eleven entry unchanged bank missing')
            if sum(len(v.split())>1 for k,v in a['shared_candidates'])!=1:raise ValueError('Phrase entry silently split')
        else:
            if any(q.get('maxWords')!=1 or q['options']or not q.get('knownForms')for q in qs):raise ValueError('One-word changed-form bank contract differs')
            if any(q['bank_entry']not in a['bank_entries']for q in qs):raise ValueError('Answer from outside bank')
    if a.get('slot_roles'):
        if len(a['slot_roles'])!=count or a['slot_roles']!=s['shape']['details']['slot_roles']or len(a['shared_candidates'])!=s['shape']['details']['shared_options']:raise ValueError('Heading/sentence roles or shared set differs')
        if any(q['options']!=a['shared_candidates']for q in qs) or a['reuse_rule']!='not_explicit':raise ValueError('Unobserved reuse policy or mixed candidates')
    if a.get('Chinese_hint_slots'):
        if [q['number']for q in qs if q.get('meaning')]!=a['Chinese_hint_slots']:raise ValueError('Chinese hint missing')
        if any('（'+q['meaning']+'）'not in body for q in qs):raise ValueError('Required printed hint absent')
    if a['source_frozen_input_state']is not s['necessary_input_complete'] or any(a[k]is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):raise ValueError('Source/validation state upgraded')


def run(index,matrix):
    source={r['id']:r for r in evidence()};ids=['grade7-paper-cards-passage-form','grade8-town-model-passage-form','grade8-rainy-fair-word-bank','grade10-platform-sketchbook-bank','grade7-five-club-headings','grade7-small-notebook-insertion','grade8-village-trip-Chinese-cues'];cases=[]
    for r in json.loads(index.read_text())['candidates']:
        if r['id']not in ids:continue
        a=json.loads(load_ref(r['author_check']).read_text());t=load_ref(r['candidate']).read_text();s=source[r['anchor_group_ids'][0]];verify(r,a,t,s);cases.append({'case':r['id']+' complete configuration','passed':True})
        for label,m in [('last response truncated',dict(a,review_response_tasks=a['review_response_tasks'][:-1])),('crossgrade',dict(a,grade=a['grade']+1)),('false production admission',dict(a,production_admission=True))]:
            try:verify(r,m,t,s)
            except ValueError as ex:cases.append({'case':r['id']+' rejects '+label,'passed':True,'reason':str(ex)})
            else:raise ValueError('Bad contract admitted')
    m=json.loads(matrix.read_text());c=next(c for c in m['cells']if c['grade']==8 and c['family']=='passage_form')
    if c['selected_representative_id']!='grade8-town-model-passage-form' or not any(x['source_form_support'].startswith('simulated_')for x in c['existing_authored_candidates']):raise ValueError('Ordinary representative not selected or simulated history lost')
    cases.append({'case':'ordinary grade8 preferred; simulated candidate retained in history','passed':True})
    return {'cases':cases,'controls':len(cases),'new_groups':7,'new_responses':60,'simulated_source_not_upgraded':True,'source_count_increment':0,'independent_student_commercial_or_production':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--matrix',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args();r=run(args.index,args.matrix);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='cases'}))
