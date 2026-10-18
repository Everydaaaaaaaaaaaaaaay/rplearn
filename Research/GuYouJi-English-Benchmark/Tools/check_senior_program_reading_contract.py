#!/usr/bin/env python3
"""Reject incomplete programme profiles, lost booking/age inputs and wrong source scores."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from senior_reading_contract import validate,check,digest


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan']);idx=json.loads(load_ref(plan['current_gap_completion']).read_text());records=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('source_bound_four_program_reading_section'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());check(data['groups'][m['id']],a,b,s);cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'single_passage_substitute':lambda x:x['sections'].__delitem__(slice(1,None)),
            'missing_fourth_program':lambda x:x['sections'][0]['units'].pop(),
            'missing_booking_intro':lambda x:x['sections'][0].__setitem__('intro',''),
            'wrong_subgroup_response_range':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3,4]),
            'wrong_material':lambda x:x['questions'][3].__setitem__('materialLabel','A'),
            'wrong_genre':lambda x:x['sections'][1].__setitem__('genre','first_person_parent_essay'),
            'wrong_grade':lambda x:x.__setitem__('grade',12),
            'wrong_source':lambda x:x.__setitem__('source_group_id','other-paper'),
            'other_source2_5points':lambda x:x['questions'][0].__setitem__('points',2.5),
            'other_source37_5total':lambda x:x.__setitem__('instruction',x['instruction'].replace('30分','37.5分')),
            'missing_option':lambda x:x['questions'][0]['options'].pop(),
            'duplicate_option':lambda x:x['questions'][0]['options'][1].__setitem__(1,x['questions'][0]['options'][0][1]),
            'missing_candidate_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'empty_key':lambda x:x['questions'][0].__setitem__('answer',''),
            'paid_policy_claim':lambda x:x['program_policy'].__setitem__('all_free',False),
            'unbooked_policy_claim':lambda x:x['program_policy'].__setitem__('all_require_advance_booking',False),
            'intro_policy_text_altered':lambda x:x['sections'][0].__setitem__('intro',x['sections'][0]['intro'].replace(x['program_policy']['student_policy_text'],'No booking needed.')),
            'missing_age_profile':lambda x:x['program_policy']['targeted_age_bands'].pop(),
            'age_band_missing_from_material':lambda x:x['sections'][0]['units'].__setitem__(1,x['sections'][0]['units'][1].replace(x['program_policy']['targeted_age_bands'][1],'some families')),
            'wrong_target_age_profile':lambda x:x['program_match'].__setitem__('profile_index',2),
            'wrong_program_option_binding':lambda x:x['program_match']['option_profile_indices'].__setitem__('A',(x['program_match']['option_profile_indices']['A']+1)%4),
            'monthly_comparison_input_lost':lambda x:x['sections'][0]['units'].__setitem__(3,x['sections'][0]['units'][3].replace('once each month','on some dates')),
            'C_context_mark_missing':lambda x:x['sections'][2]['units'].__setitem__(0,x['sections'][2]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'wrong_context_word':lambda x:x.__setitem__('lexical_target','unseenword'),
            'only_two_research_conditions':lambda x:x['research_conditions'].pop(),
            'research_condition_not_in_material':lambda x:x['research_conditions'].__setitem__(0,'absent-condition'),
            'comparison_operation_lost':lambda x:x['questions'][12].__setitem__('operation','three_independent_experiments'),
            'scope_limit_lost':lambda x:x['research_scope'].__setitem__('limitations',''),
            'real_world_fact_claim':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
        };rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid programme draft accepted: '+name)
        for name,mut in {
            'source_missing_entry_spans':lambda x:x['source_A_program_entries'].pop(),
            'source_unbound_profiles':lambda x:x.__setitem__('program_profile_entry_spans_bound',False),
            'source_wrong_intro_SHA':lambda x:x['source_A_program_intro'].__setitem__('sha256','0'*64),
            'source_wrong_points':lambda x:x['configuration'].__setitem__('points_each',2.5),
            'source_gold_promotion':lambda x:x.__setitem__('source_key_is_gold',True),
        }.items():
            bad=copy.deepcopy(s);mut(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,ensure_ascii=False,sort_keys=True))
            try:validate(d,bb,bad)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        records.append(dict(id=m['id'],responses=15,candidate_positions=60,text_units=7,whole_contract_passed=True,negative_controls=rejected))
    assert records
    return dict(records=records,complete_groups=len(records),responses=sum(x['responses']for x in records),candidate_positions=sum(x['candidate_positions']for x in records),negative_controls=sum(len(x['negative_controls'])for x in records),not_independent_semantic_or_student_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
