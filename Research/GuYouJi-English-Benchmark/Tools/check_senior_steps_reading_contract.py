#!/usr/bin/env python3
"""Exercise complete 20-response input, evidence pins and specific unit boundaries."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from senior_reading_contract import validate, check


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan'])
    idx=json.loads(load_ref(plan['current_gap_completion']).read_text());records=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('source_bound_steps_letter_migration_survey'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());g=data['groups'][m['id']]
        check(g,a,b,s)
        cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'fixed_fifteen_truncation':lambda x:x['questions'].__delitem__(slice(15,None)),
            'only_A_material':lambda x:x['sections'].__delitem__(slice(1,None)),
            'missing_D_material':lambda x:x['sections'][-1].__setitem__('units',['']),
            'other_15response_distribution':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3]),
            'wrong_material_link':lambda x:x['questions'][5].__setitem__('materialLabel','A'),
            'wrong_grade':lambda x:x.__setitem__('grade',11),
            'wrong_source':lambda x:x.__setitem__('source_group_id','other'),
            'wrong2points':lambda x:x['questions'][0].__setitem__('points',2),
            'wrong37_5total':lambda x:x.__setitem__('instruction',x['instruction'].replace('50分','37.5分')),
            'missing_fourth_candidate':lambda x:x['questions'][0]['options'].pop(),
            'missing_candidate_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'missing_step4':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].split('\n4. ')[0]),
            'reordered_step_number':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].replace('\n4. ','\n3. ')),
            'step_heading_without_example':lambda x:x['sections'][0]['units'].__setitem__(0,'Advice.\n\n'+'\n'.join(str(i)+'. '+t for i,t in enumerate(x['steps'],1))),
            'letter_salutation_lost':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].removeprefix(x['letter']['salutation']+'\n\n')),
            'letter_closing_lost':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].removesuffix('\n\n'+x['letter']['closing'])),
            'letter_generation_lost':lambda x:x['letter']['chain'].__setitem__(1,'an absent generation'),
            'letter_quote_drift':lambda x:x['letter'].__setitem__('quote','A quotation that does not occur.'),
            'caught_equal_to_tracked':lambda x:x['migration'].__setitem__('caught',x['migration']['tracked']),
            'sampled_equals_caught':lambda x:x['migration'].__setitem__('sampled',x['migration']['caught']),
            'flights_equals_individuals':lambda x:x['migration'].__setitem__('flights',x['migration']['tracked']),
            'count_changed_without_input':lambda x:x['migration'].__setitem__('caught',x['migration']['caught']+1),
            'unit_boundary_lost':lambda x:x['migration_evidence'].__setitem__('flights_are_not_individuals',False),
            'annual_counts_invented':lambda x:x['migration_evidence'].__setitem__('counts_are_project_totals',False),
            'projection_as_observation':lambda x:x['migration_evidence'].__setitem__('projection_not_observed_future',False),
            'conditional_assumption_lost':lambda x:x['sections'][2]['units'].__setitem__(0,x['sections'][2]['units'][0].replace(x['migration']['condition'],'The model guarantees')),
            'observed_result_lost':lambda x:x['migration'].__setitem__('observation','No birds were tracked.'),
            'survey_scales_merged':lambda x:x['survey'].__setitem__('second_scale','0 to 10'),
            'survey_constructs_merged':lambda x:x['survey_evidence'].__setitem__('separate_constructs_cohorts_and_scales',False),
            'panel_invented':lambda x:x['survey_evidence'].__setitem__('fresh_samples_not_individual_panel',False),
            'causal_upgrade':lambda x:x['survey_evidence'].__setitem__('association_not_causation',False),
            'age_order_reversed':lambda x:x['survey']['first_young'].reverse(),
            'school_score_out_of_scale':lambda x:next(iter(x['survey']['second_cohorts'].values())).__setitem__(0,8.0),
            'original_facts_claimed':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
            'missing_answer_evidence':lambda x:x['answer_evidence'].pop(),
            'unreported_answer_evidence':lambda x:x['answer_evidence'][0].__setitem__('evidence','An unsupported claim which occurs in no material.'),
        }
        rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid steps draft accepted: '+name)
        for number in range(20):
            bad=copy.deepcopy(d);q=bad['questions'][number]
            q['answer']=next(k for k,_ in q['options']if k!=q['answer'])
            try:validate(bad,b,s)
            except AssertionError:rejected.append('answer_text_pin_drift_Q'+str(number+1))
            else:raise AssertionError('Changed key accepted')
        for name,old,new in [('lost_ordered_list','<ol class="reading-activities">','<div>'),('lost_step4_value','<li value="4">','<li value="3">')]:
            broken=copy.deepcopy(g);broken['passageHtml']=broken['passageHtml'].replace(old,new,1)
            try:check(broken,a,b,s)
            except AssertionError:rejected.append(name)
            else:raise AssertionError('Lost semantic steps accepted')
        records.append(dict(id=m['id'],responses=20,candidate_positions=80,ordered_steps=4,full_letter=True,negative_controls=rejected,whole_contract_passed=True))
    assert len(records)==3
    return dict(records=records,complete_groups=3,responses=60,candidate_positions=240,negative_controls=sum(len(r['negative_controls'])for r in records),not_independent_best_answer_or_difficulty_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='records'}))
