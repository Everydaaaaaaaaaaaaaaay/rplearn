#!/usr/bin/env python3
"""Reject incomplete job-reading inputs, endpoint mistakes and key drift."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from senior_reading_contract import validate,check
from senior_job_reading_contract import notice,applicant_text


def update_job(d,fn):
    fn(d['job_notice']);d['sections'][0]['units']=[notice(d['job_notice'])]


def update_profile(d,label,fn):
    fn(d['applicant_options'][label]);d['questions'][1]['options']=[
        [key,applicant_text(d['applicant_options'][key],d.get('applicant_render_version','0.1'))]for key,_ in d['questions'][1]['options']]


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan'])
    idx=json.loads(load_ref(plan['current_gap_completion']).read_text());out=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('source_bound_job_notice_reading_section'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());g=data['groups'][m['id']];check(g,a,b,s)
        best=d['questions'][1]['answer'];other=next(k for k,c in d['applicant_options'].items()if c['age']==20)
        cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'only_A_input':lambda x:x['sections'].__delitem__(slice(1,None)),
            'D_input_lost':lambda x:x['sections'][-1].__setitem__('units',['']),
            'A_four_response_wrong_configuration':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3,4]),
            'wrong_material_link':lambda x:x['questions'][3].__setitem__('materialLabel','A'),
            'wrong_grade':lambda x:x.__setitem__('grade',10),
            'wrong_source':lambda x:x.__setitem__('source_group_id','other'),
            'wrong_each2points':lambda x:x['questions'][0].__setitem__('points',2),
            'whole50_as_first37_5':lambda x:x.__setitem__('instruction',x['instruction'].replace('37.5分','50分')),
            'missing_option':lambda x:x['questions'][0]['options'].pop(),
            'missing_candidate_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'A_final_challenge_missing':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].split('#### Work challenges')[0]),
            'age_minimum_raised_to22':lambda x:update_job(x,lambda j:j.__setitem__('minimum_age',22)),
            'three_year_endpoint_excluded':lambda x:x['job_notice'].__setitem__('license_endpoint_inclusive',False),
            'expired_licence_allowed':lambda x:x['job_notice'].__setitem__('current_license_required',False),
            'spring_and_summer_days_merged':lambda x:update_job(x,lambda j:j.__setitem__('spring_days','Monday to Friday')),
            'weekly_hours_changed':lambda x:update_job(x,lambda j:j.__setitem__('weekly_hours',20)),
            'fortnight_pay_changed':lambda x:update_job(x,lambda j:j.__setitem__('pay_every_weeks',4)),
            'weekly_pay_changed':lambda x:update_job(x,lambda j:j.__setitem__('weekly_pay',1500)),
            'preferred_work_mandatory':lambda x:x['job_notice'].__setitem__('preferred_not_mandatory',[]),
            'certificates_after_fieldwork':lambda x:x['job_notice'].__setitem__('certificates_before_field_duties',False),
            'training_availability_removed':lambda x:x['job_notice'].__setitem__('training_before_placement_available',False),
            'best_candidate_below_age_with_consistent_text':lambda x:update_profile(x,best,lambda c:c.__setitem__('age',20)),
            'best_candidate_below_tenure_with_consistent_text':lambda x:update_profile(x,best,lambda c:c.__setitem__('licensed_years',2)),
            'best_candidate_expired_with_consistent_text':lambda x:update_profile(x,best,lambda c:c.__setitem__('current',False)),
            'two_eligible_candidates_with_consistent_text':lambda x:update_profile(x,other,lambda c:c.__setitem__('age',21)),
            'unstated_other_requirements_assumption':lambda x:x.__setitem__('applicant_other_requirements_assumed_met',False),
            'B_context_word_mark_missing':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'C_same_total_as_same_ownership':lambda x:x['survey'].__setitem__('same_reported_total_share_not_same_chore_ownership',False),
            'C_randomisation_invented':lambda x:x['survey'].__setitem__('existing_arrangements_not_random_assignment',False),
            'C_causal_direction_settled':lambda x:x['survey'].__setitem__('alternative_causal_directions_not_adjudicated',False),
            'C_count_changed_without_input':lambda x:x['survey'].__setitem__('joint_fair',x['survey']['joint_fair']+1),
            'C_quote_not_in_input':lambda x:x.__setitem__('C_quote','An absent quotation.'),
            'D_seven_digits_invented':lambda x:x['robot'].__setitem__('digit_total',7),
            'D_support_and_carry_exceed_total':lambda x:x['robot']['support_carry_modes'].__setitem__(0,[5,2]),
            'D_six_digits_as_source_literal_fact':lambda x:x['robot'].__setitem__('six_digits_explicit_authored_choice_not_source_literal_claim',False),
            'D_simulation_test_evidence_lost':lambda x:x['robot'].__setitem__('simulation_testing_evidence','An unreported design process.'),
            'D_future_control_closed':lambda x:x.__setitem__('future_human_control_open',False),
            'D_human_validation_upgrade':lambda x:x.__setitem__('human_interface_or_clinical_benefit_validated',True),
            'D_limit_missing':lambda x:x['research_scope'].__setitem__('limitations',''),
            'real_studies_claimed':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
            'answer_evidence_lost':lambda x:x['answer_evidence'].pop(),
        }
        rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid job draft accepted: '+name)
        for n in range(15):
            bad=copy.deepcopy(d);q=bad['questions'][n];q['answer']=next(k for k,_ in q['options']if k!=q['answer'])
            try:validate(bad,b,s)
            except AssertionError:rejected.append('key_text_pin_drift_Q'+str(n+1))
            else:raise AssertionError('Changed key accepted')
        broken=copy.deepcopy(g);broken['passageHtml']=broken['passageHtml'].replace('<h3>Qualifications</h3>','<p>Qualifications</p>')
        try:check(broken,a,b,s)
        except AssertionError:rejected.append('advert_heading_semantic_render_lost')
        else:raise AssertionError('Lost qualification heading accepted')
        out.append(dict(id=m['id'],responses=15,candidates=60,advert_headings=6,whole_contract_passed=True,negative_controls=rejected))
    assert len(out)==3
    return dict(records=out,complete_groups=3,responses=45,candidate_positions=180,negative_controls=sum(len(r['negative_controls'])for r in out),not_independent_answer_difficulty_or_production_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen proof must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='records'}))
