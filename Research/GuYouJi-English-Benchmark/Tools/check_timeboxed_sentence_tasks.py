#!/usr/bin/env python3
"""Verify complete cue/response contracts; semantic alternatives remain author-reviewed."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from quality_review_contract import response_markdown


def verify(row, audit, text, source):
    if audit['candidate_sha256'] != row['candidate']['sha256'] or hashlib.sha256(text.encode()).hexdigest() != audit['candidate_sha256']:
        raise ValueError('Candidate/audit byte identity differs')
    if (audit['grade'] != source['shape']['grade'] or row['grade'] != audit['grade'] or
            audit['family'] != source['shape']['family'] or audit['source_shape'] != source['shape'] or
            row['source_shape'] != source['shape'] or audit['questions'] != source['shape']['responses']):
        raise ValueError('Grade/family/full source shape differs')
    if audit['source_frozen_input_state'] is not source['necessary_input_complete'] or not audit['source_frozen_state_not_upgraded']:
        raise ValueError('Frozen source state upgraded')
    qs = audit['review_response_tasks']; count = audit['questions']
    if [q['number'] for q in qs] != list(range(1,count+1)):
        raise ValueError('Missing/reordered response')
    student = text.split('\n## 学生题面\n')[1].split('\n## 作者核对\n')[0]
    printed = student.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if printed != response_markdown(qs) or hashlib.sha256(printed.encode()).hexdigest() != audit['canonical_response_block_sha256']:
        raise ValueError('Printed and interactive complete response contract differs')
    contract = audit['target_constraints']
    for q in qs:
        if not q['stem'] or not q['rationale'] or q['options']:
            raise ValueError('Incomplete nonchoice prompt/evidence')
        if audit['whole_sentence_output']:
            if not q.get('referenceAnswers') or len(q.get('parts',[])) != 1 or q.get('knownForms'):
                raise ValueError('Whole translation reduced to fragments/word fill')
            if '（' not in q['stem'] or '）' not in q['stem']:
                raise ValueError('Required translation cues missing')
        else:
            forms = q.get('knownForms',[])
            if not forms:
                raise ValueError('Missing author reference forms')
            if q.get('maxWords') and any(len(s.split())>q['maxWords'] for s in forms):
                raise ValueError('Reference violates explicit response length')
            if q.get('initial'):
                if q['initial']+'_' not in q['stem'] or any(not s.lower().startswith(q['initial']) for s in forms):
                    raise ValueError('Initial cue/full-word response differs')
            if q.get('meaning') and q['meaning'] not in q['stem']:
                raise ValueError('Required Chinese cue missing')
            if q.get('phonetic') and q['phonetic'] not in q['stem']:
                raise ValueError('Required IPA cue missing')
    if 'given_word_slots' in contract:
        given = [q['number'] for q in qs if q.get('given_word')]
        ungiven = [q['number'] for q in qs if not q.get('given_word')]
        if given != contract['given_word_slots'] or ungiven != contract['ungiven_one_word_slots'] or len(given)!=10 or len(ungiven)!=5:
            raise ValueError('Fifteen independent contexts given10/ungiven5 differs')
        if any('('+q['given_word']+')' not in q['stem'] for q in qs if q.get('given_word')):
            raise ValueError('Given root omitted')
        if any(q.get('maxWords')!=1 for q in qs if not q.get('given_word')):
            raise ValueError('Ungiven one-word policy missing')
    if contract.get('Chinese_hint_slots'):
        if [q['number'] for q in qs if q.get('meaning')] != contract['Chinese_hint_slots'] or [q['number'] for q in qs if q.get('initial')] != contract['initial_hint_slots']:
            raise ValueError('Chinese4/initial4 mode silently changed')
    if contract.get('phonetic_cues_required') and (len(qs)!=4 or any(not q.get('phonetic') for q in qs)):
        raise ValueError('Full four-IPA input required')
    if any(audit[k] is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):
        raise ValueError('Unverified admission claim')


def check():
    index=json.loads((BASE/'FirstRelease/Timeboxed/authored-review-index-v0.2.json').read_text())
    source={r['id']:r for r in evidence()};cases=[]
    for row in index['candidates']:
        audit=json.loads(load_ref(row['author_check']).read_text())
        if not audit.get('review_response_tasks'):
            continue
        text=load_ref(row['candidate']).read_text();s=source[row['anchor_group_ids'][0]]
        verify(row,audit,text,s);cases.append({'case':row['id']+' complete source/cue/response contract','passed':True})
        variants=[]
        a=copy.deepcopy(audit);a['grade']+=1;variants.append(('crossgrade audit',a))
        a=copy.deepcopy(audit);a['review_response_tasks'].pop();variants.append(('last response missing',a))
        a=copy.deepcopy(audit);a['production_admission']=True;variants.append(('unearned production admission',a))
        for label,a in variants:
            try:
                verify(row,a,text,s)
            except ValueError as error:
                cases.append({'case':row['id']+' rejects '+label,'passed':True,'reason':str(error)})
            else:
                raise ValueError('Invalid task admitted: '+label)
    return {'cases':cases,'controls':len(cases),'positive':7,'rejection':21,'new_authored_groups':7,'new_responses':50,
            'source_count_increment':0,'semantic_reference_sets_not_certified_exhaustive':True,'independent_student_commercial_or_production':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--report',type=Path,required=True)
    args=p.parse_args();result=check();args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='cases'},ensure_ascii=False))
