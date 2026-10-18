#!/usr/bin/env python3
"""Reject partial sections, lost text units and unbound reading configurations."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from school_reading_contract import check,validate,digest


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan'])
    idx=json.loads(load_ref(plan['current_gap_completion']).read_text());records=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('school_complete_reading_section'):continue
        b=next(b for b in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if b['id']==a['source_binding'])
        s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==b['source_group_id'])
        check(data['groups'][m['id']],a,b,s);d=json.loads(load_ref(a['manuscript']).read_text());rejected=[]
        cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'single_passage_substitute':lambda x:x['sections'].__delitem__(slice(1,None)),
            'missing_fourth_A_profile':lambda x:x['sections'][0]['units'].pop(),
            'merged_two_B_letters':lambda x:x['sections'][1].__setitem__('units',['\n\n'.join(x['sections'][1]['units'])]),
            'missing_E_conclusion':lambda x:x['sections'][4].__setitem__('units',[]),
            'reordered_subgroups':lambda x:x['sections'].reverse(),
            'wrong_material_association':lambda x:x['questions'][3].__setitem__('materialLabel','A'),
            'wrong_response_number':lambda x:x['questions'][-1].__setitem__('number',18),
            'wrong_question_points':lambda x:x['questions'][0].__setitem__('points',1),
            'duplicate_option_label':lambda x:x['questions'][0]['options'][1].__setitem__(0,'A'),
            'duplicate_option_text':lambda x:x['questions'][0]['options'][1].__setitem__(1,x['questions'][0]['options'][0][1]),
            'missing_candidate_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'multi_label_key':lambda x:x['questions'][0].__setitem__('answer','AB'),
            'empty_key':lambda x:x['questions'][0].__setitem__('answer',''),
            'missing_reference_mark':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].replace('**it**','it')),
            'wrong_reference_profile':lambda x:x['sections'][0]['units'].reverse(),
            'missing_context_word_mark':lambda x:x['sections'][2]['units'].__setitem__(0,x['sections'][2]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'wrong_lexical_target':lambda x:x.__setitem__('lexical_target','unseenword'),
            'negative_item_type_lost':lambda x:x['questions'][15].__setitem__('operation','unknown_information'),
            'title_item_type_lost':lambda x:x['questions'][16].__setitem__('operation','single_detail'),
            'wrong_grade':lambda x:x.__setitem__('grade',8),
            'wrong_source':lambda x:x.__setitem__('source_group_id','different-section'),
            'old_40point_scope_claim':lambda x:x.__setitem__('instruction',x['instruction'].replace('34分','40分')),
            'open_section_boundary_omitted':lambda x:x.__setitem__('source_notice',x['source_notice'].replace('第二节','另一节')),
        }
        for name,mutate in cases.items():
            bad=copy.deepcopy(d);mutate(bad)
            try:validate(bad,b,s)
            except (AssertionError,IndexError,ValueError,KeyError):rejected.append(name)
            else:raise AssertionError('Invalid authored reading accepted: '+name)
        source_cases={
            'source_not_full':lambda x:x.__setitem__('source_full_inputs_verified',False),
            'source_promoted_gold':lambda x:x.__setitem__('source_key_is_gold',True),
            'source_header_digest_wrong':lambda x:x['whole_objective_header'].__setitem__('sha256','0'*64),
            'source_missing_subgroup_span':lambda x:x['source_spans'].pop(),
            'source_body_digest_wrong':lambda x:x['source_spans'][0].__setitem__('sha256','0'*64),
            'source_parent_changed':lambda x:x['source_observations'][1].__setitem__('paper_id','other-paper'),
            'source_one_B_letter_claim':lambda x:x['configuration']['subgroups'][1].__setitem__('material_units',1),
            'source_optional_subgroups_claim':lambda x:x['configuration'].__setitem__('all_selected_subgroups_mandatory',False),
            'source_open_F_included':lambda x:x['configuration'].__setitem__('excluded_open_response_numbers',[]),
            'source_whole40_claimed_as_objective34':lambda x:x['configuration'].__setitem__('whole_reading_points',34),
            'source_cartesian_3_options':lambda x:x.__setitem__('options_each',3),
        }
        for name,mutate in source_cases.items():
            bad=copy.deepcopy(s);mutate(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,sort_keys=True,ensure_ascii=False))
            try:validate(d,bb,bad)
            except (AssertionError,IndexError,ValueError,KeyError):rejected.append(name)
            else:raise AssertionError('Invalid source reading accepted: '+name)
        records.append(dict(id=m['id'],response_positions=17,candidate_positions=68,text_units=9,subgroup_counts=[3,4,4,3,3],negative_controls=rejected,positive_whole_contract=True))
    assert records
    return dict(records=records,complete_groups=len(records),response_positions=sum(r['response_positions']for r in records),candidate_positions=sum(r['candidate_positions']for r in records),negative_controls=sum(len(r['negative_controls'])for r in records),not_independent_semantic_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();result=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result))
