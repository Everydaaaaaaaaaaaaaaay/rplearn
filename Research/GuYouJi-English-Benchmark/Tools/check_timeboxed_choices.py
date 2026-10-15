#!/usr/bin/env python3
"""Check full sentence-choice contracts without mistaking checks for semantic calibration."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from quality_review_contract import response_markdown


def verify(row, audit, text, source):
    if audit['candidate_sha256'] != row['candidate']['sha256'] or hashlib.sha256(text.encode()).hexdigest() != audit['candidate_sha256']:
        raise ValueError('Candidate digest differs')
    if (audit['grade'] != row['grade'] or audit['grade'] != source['shape']['grade'] or
            audit['source_shape'] != row['source_shape'] or audit['source_shape'] != source['shape'] or
            audit['family'] != 'sentence_choice' or audit['family'] != source['shape']['family']):
        raise ValueError('Grade/family/exact source shape differs')
    count=source['shape']['responses']; opts=source['shape']['options_each']; qs=audit['review_response_tasks']
    if audit['questions'] != count or [q['number'] for q in qs] != list(range(1,count+1)):
        raise ValueError('Full response sequence differs')
    if opts != audit['options_each'] or any([x[0] for x in q['options']] != list('ABCD')[:opts] for q in qs):
        raise ValueError('Per-question candidate set differs')
    for q in qs:
        checks=q['author_option_checks']
        if len(checks)!=opts or [x['label'] for x in checks]!=list('ABCD')[:opts] or any(not x['reason'] for x in checks):
            raise ValueError('Unreviewed candidate position')
        if [x['label'] for x in checks if x['valid']] != [q['answer']] or not q['rationale']:
            raise ValueError('Single author key/reasons differ')
        if q['visible_gap_count']!=q['stem'].count('________') or not q['one_response_for_all_gaps']:
            raise ValueError('Composite gaps split or omitted')
    block=text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()
    if block != response_markdown(qs) or hashlib.sha256(block.encode()).hexdigest()!=audit['canonical_response_block_sha256']:
        raise ValueError('Printed and interactive tasks differ')
    c=audit['target_constraints']
    if c['visible_gaps']!=sum(q['visible_gap_count'] for q in qs) or c['composite_gap_questions']!=[q['number'] for q in qs if q['visible_gap_count']>1]:
        raise ValueError('Visible gaps/response count conflated')
    if audit['source_frozen_input_state'] is not source['necessary_input_complete'] or not audit['source_frozen_state_not_upgraded']:
        raise ValueError('Source state upgraded')
    if any(audit[k] is not False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called']):
        raise ValueError('Unearned validation claim')


def run(index):
    rows={r['id']:r for r in evidence()}; cases=[]; counts=[0,0,0]
    for row in json.loads(index.read_text())['candidates']:
        if row['family']!='sentence_choice':continue
        a=json.loads(load_ref(row['author_check']).read_text());t=load_ref(row['candidate']).read_text();s=rows[row['anchor_group_ids'][0]]
        verify(row,a,t,s);cases.append({'case':row['id']+' complete contract','passed':True})
        if row['grade']==7:
            tr=json.loads(load_ref(a['source_reference']['transcription']).read_text());record=tr['records'][a['source_reference']['record_index']]
            if record['id']!=s['id'] or a['source_printed_question_numbers']!=record['printed_numbers']:
                raise ValueError('Printed source numbering differs')
        variants=[]
        m=copy.deepcopy(a);m['review_response_tasks'].pop();variants.append(('last task missing',m))
        m=copy.deepcopy(a);m['review_response_tasks'][0]['options'].pop();variants.append(('last candidate missing',m))
        m=copy.deepcopy(a);m['grade']+=1;variants.append(('wrong grade',m))
        m=copy.deepcopy(a);m['production_admission']=True;variants.append(('production claim',m))
        for label,m in variants:
            try:verify(row,m,t,s)
            except ValueError as ex:cases.append({'case':row['id']+' rejects '+label,'passed':True,'reason':str(ex)})
            else:raise ValueError('Broken contract admitted '+label)
        counts[0]+=len(a['review_response_tasks']);counts[1]+=a['all_option_positions_same_author_reviewed'];counts[2]+=a['target_constraints']['visible_gaps']
    return {'cases':cases,'controls':len(cases),'new_groups':5,'responses':counts[0],'options':counts[1],'visible_gaps':counts[2],
            'semantic_quality':'same author review only;not independent answer gold or student calibration','source_count_increment':0}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
    args=p.parse_args();r=run(args.index);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='cases'}))
