#!/usr/bin/env python3
"""Exercise four-book senior sections against truncation and lost source conditions."""
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
        if not a.get('school_complete_senior_reading_section')or a.get('source_bound_three_passage_fee_table_section'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());check(data['groups'][m['id']],a,b,s);bad_cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'only_first_passage':lambda x:x['sections'].__delitem__(slice(1,None)),
            'lost_final_research_report':lambda x:x['sections'][-1].__setitem__('units',['']),
            'lost_fourth_book':lambda x:x['sections'][0]['units'].pop(),
            'lost_book_intro':lambda x:x['sections'][0].__setitem__('intro',''),
            'reordered_passages':lambda x:x['sections'].reverse(),
            'wrong_B_genre':lambda x:x['sections'][1].__setitem__('genre','single_service_notice'),
            'wrong_material_link':lambda x:x['questions'][3].__setitem__('materialLabel','A'),
            'wrong_response_distribution':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3,4]),
            'wrong_question_number':lambda x:x['questions'][-1].__setitem__('number',16),
            'wrong_point_allocation':lambda x:x['questions'][0].__setitem__('points',2),
            'three_options':lambda x:x['questions'][0]['options'].pop(),
            'duplicate_option_label':lambda x:x['questions'][0]['options'][1].__setitem__(0,'A'),
            'duplicate_option_text':lambda x:x['questions'][0]['options'][1].__setitem__(1,x['questions'][0]['options'][0][1]),
            'missing_option_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'empty_key':lambda x:x['questions'][0].__setitem__('answer',''),
            'two_choice_key':lambda x:x['questions'][0].__setitem__('answer','AB'),
            'wrong_grade':lambda x:x.__setitem__('grade',11),
            'wrong_source_identity':lambda x:x.__setitem__('source_group_id','different-paper'),
            'wrong_binding':lambda x:x.__setitem__('source_binding','different-binding'),
            'real_fact_claim':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
            'inflated_total':lambda x:x.__setitem__('instruction',x['instruction'].replace('37.5分','50分')),
            'lost_context_word_mark':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'wrong_context_word':lambda x:x.__setitem__('lexical_target','unseenword'),
            'lost_research_limitation':lambda x:x['research_scope'].__setitem__('limitations',''),
            'lost_application_operation':lambda x:x['questions'][14].__setitem__('operation','detail_only'),
        };rejected=[]
        for name,mut in bad_cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,ValueError,IndexError):rejected.append(name)
            else:raise AssertionError('Invalid author accepted: '+name)
        for name,mut in {
            'source_not_ready':lambda x:x.update(authors_genre_model_ready=False,genre_substructure_further_review_before_authoring=True),
            'source_gold_promotion':lambda x:x.__setitem__('source_key_is_gold',True),
            'missing_source_body':lambda x:x['source_spans'].pop(),
            'source_wrong_points':lambda x:x['configuration'].__setitem__('points_each',2),
            'source_missing_book_entry':lambda x:x['source_A_book_entries'].pop(),
        }.items():
            bad=copy.deepcopy(s);mut(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,ensure_ascii=False,sort_keys=True))
            try:validate(d,bb,bad)
            except (AssertionError,KeyError,ValueError,IndexError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        records.append(dict(id=m['id'],responses=len(d['questions']),candidate_positions=len(a['question_candidate_audit']),text_units=sum(len(x['units'])for x in d['sections']),whole_section_contract_passed=True,negative_controls=rejected))
    assert records
    return dict(records=records,complete_groups=len(records),responses=sum(x['responses']for x in records),candidate_positions=sum(x['candidate_positions']for x in records),negative_controls=sum(len(x['negative_controls'])for x in records),not_independent_semantic_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
