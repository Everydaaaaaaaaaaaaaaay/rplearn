#!/usr/bin/env python3
"""Reject lost credit conditions, arithmetic/date key drift and truncated sections."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from senior_reading_contract import validate,check,digest
from senior_credit_reading_contract import notice


def update_policy(d,fn):
    fn(d['credit_notice']);d['sections'][0]['units']=[notice(d['credit_notice'])]


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan']);idx=json.loads(load_ref(plan['current_gap_completion']).read_text());records=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('source_bound_credit_notice_reading_section'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());g=data['groups'][m['id']];check(g,a,b,s);cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'only_first_passage':lambda x:x['sections'].__delitem__(slice(1,None)),
            'lost_final_mechanism':lambda x:x['sections'][-1].__setitem__('units',['']),
            'wrong_response_distribution':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3,4]),
            'wrong_material_link':lambda x:x['questions'][3].__setitem__('materialLabel','A'),
            'wrong_grade':lambda x:x.__setitem__('grade',11),
            'wrong_source':lambda x:x.__setitem__('source_group_id','different-paper'),
            'other_source2points':lambda x:x['questions'][0].__setitem__('points',2),
            'other_source30total':lambda x:x.__setitem__('instruction',x['instruction'].replace('37.5分','30分')),
            'missing_option':lambda x:x['questions'][0]['options'].pop(),
            'duplicate_option':lambda x:x['questions'][0]['options'][1].__setitem__(1,x['questions'][0]['options'][0][1]),
            'empty_key':lambda x:x['questions'][0].__setitem__('answer',''),
            'two_keys':lambda x:x['questions'][0].__setitem__('answer','AB'),
            'missing_candidate_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'missing_half_credit_line':lambda x:update_policy(x,lambda p:p['compulsory'].pop()),
            'half_credits_changed_to_full':lambda x:update_policy(x,lambda p:p['compulsory'][-1].__setitem__('credits',1)),
            'arithmetic_drift_same_material_policy':lambda x:update_policy(x,lambda p:p['compulsory'][0].__setitem__('credits',p['compulsory'][0]['credits']+1)),
            'optional_total_drift_same_material_policy':lambda x:update_policy(x,lambda p:p.__setitem__('optional_credits',p['optional_credits']+1)),
            'online_credits_added_as_extra':lambda x:x['credit_notice'].__setitem__('online_included_in_total',False),
            'wrong_online_count':lambda x:update_policy(x,lambda p:p.__setitem__('online_credits',3)),
            'partner_cap_exceeds_optional_total':lambda x:update_policy(x,lambda p:p.__setitem__('dual_credit_cap',p['optional_credits']+1)),
            'community_hours_as_credit_answer':lambda x:x['questions'][0].__setitem__('answer',next(label for label,_ in x['questions'][0]['options']if label!=x['questions'][0]['answer'])),
            'effective_date_drift_same_policy_material':lambda x:update_policy(x,lambda p:p.__setitem__('literacy_effective','1 December 2040')),
            'missing_online_cohort_from_stem':lambda x:x['questions'][0].__setitem__('stem',x['questions'][0]['stem'].replace(x['credit_notice']['online_cohort_start'],'another year')),
            'adult_parent_condition_invented':lambda x:x['credit_notice'].__setitem__('adult_parent_discussion_required',True),
            'adult_approval_check_removed':lambda x:x['credit_notice'].__setitem__('adult_must_verify_approval',False),
            'age_threshold_changed':lambda x:update_policy(x,lambda p:p.__setitem__('minor_age',21)),
            'hour_threshold_changed':lambda x:update_policy(x,lambda p:p.__setitem__('community_hours',4)),
            'list_student_input_lost':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].replace('- check that the proposed activity meets the school’s approval rules;','')),
            'B_lexical_mark_lost':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'C_scope_operation_lost':lambda x:x['questions'][8].__setitem__('operation','unqualified_physical_equivalence'),
            'D_mechanism_stage_missing':lambda x:x['mechanism_stages'].pop(),
            'D_stage_not_in_text':lambda x:x['mechanism_stages'].__setitem__(0,'a missing stage'),
            'future_application_not_in_text':lambda x:x.__setitem__('future_aim','an unreported application'),
            'scope_limit_lost':lambda x:x['research_scope'].__setitem__('limitations',''),
            'real_policy_or_study_claim':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
        };rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid credit draft accepted: '+name)
        for name,mut in {
            'source_credit_block_missing':lambda x:x['source_A_requirement_blocks'].pop(),
            'source_credit_block_SHA_wrong':lambda x:x['source_A_requirement_blocks'][0].__setitem__('sha256','0'*64),
            'source_credit_blocks_unbound':lambda x:x.__setitem__('credit_requirement_blocks_bound',False),
            'source_required_list_omitted':lambda x:x['configuration'].__setitem__('required_lists',[]),
            'source_gold_promotion':lambda x:x.__setitem__('source_key_is_gold',True),
        }.items():
            bad=copy.deepcopy(s);mut(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,ensure_ascii=False,sort_keys=True))
            try:validate(d,bb,bad)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        broken=copy.deepcopy(g);broken['passageHtml']=broken['passageHtml'].replace('<ul class="reading-requirements">','<p>',1)
        try:check(broken,a,b,s)
        except AssertionError:rejected.append('credit_list_semantic_render_lost')
        else:raise AssertionError('Lost rendered list accepted')
        records.append(dict(id=m['id'],responses=15,candidate_positions=60,compulsory_entries=11,half_credit_entries=2,community_condition_entries=3,whole_contract_passed=True,negative_controls=rejected))
    assert records
    return dict(records=records,complete_groups=len(records),responses=sum(x['responses']for x in records),candidate_positions=sum(x['candidate_positions']for x in records),negative_controls=sum(len(x['negative_controls'])for x in records),not_independent_semantic_or_student_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
