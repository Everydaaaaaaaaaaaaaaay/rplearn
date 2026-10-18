#!/usr/bin/env python3
"""Reject lost fee-table inputs, row/column keys and partial senior sections."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from senior_reading_contract import validate,check,digest,table_markup


def run(page):
    data=extract(page);_,plan=resolve_plan(data['active_run_plan']);idx=json.loads(load_ref(plan['current_gap_completion']).read_text());records=[]
    for m in idx['candidates']:
        a=json.loads(load_ref(m['author_check']).read_text())
        if not a.get('source_bound_three_passage_fee_table_section'):continue
        b=next(x for x in json.loads(load_ref(a['source_bindings']).read_text())['bindings']if x['id']==a['source_binding'])
        s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
        d=json.loads(load_ref(a['manuscript']).read_text());g=data['groups'][m['id']];check(g,a,b,s);cases={
            'fixed_six_truncation':lambda x:x['questions'].__delitem__(slice(6,None)),
            'single_passage_substitute':lambda x:x['sections'].__delitem__(slice(1,None)),
            'four_passages_same_total_claim':lambda x:x['sections'].append(copy.deepcopy(x['sections'][0])),
            'wrong_subgroup_response_range':lambda x:x['sections'][0].__setitem__('response_numbers',[1,2,3]),
            'wrong_material_association':lambda x:x['questions'][5].__setitem__('materialLabel','A'),
            'wrong_genre':lambda x:x['sections'][1].__setitem__('genre','third_person_event_report'),
            'wrong_grade':lambda x:x.__setitem__('grade',10),
            'wrong_source':lambda x:x.__setitem__('source_group_id','different-paper'),
            'wrong_points':lambda x:x['questions'][0].__setitem__('points',2),
            'wrong_total':lambda x:x.__setitem__('instruction',x['instruction'].replace('37.5分','30分')),
            'missing_option':lambda x:x['questions'][0]['options'].pop(),
            'duplicate_option_text':lambda x:x['questions'][0]['options'][1].__setitem__(1,x['questions'][0]['options'][0][1]),
            'missing_option_reason':lambda x:x['questions'][0].__setitem__('rationale',x['questions'][0]['rationale'].split('；')[0]),
            'two_keys':lambda x:x['questions'][0].__setitem__('answer','AB'),
            'missing_table':lambda x:x.pop('required_table'),
            'missing_table_row':lambda x:x['required_table']['cells'].pop(),
            'missing_table_column':lambda x:x['required_table']['cells'][0].pop(),
            'reversed_column_materials':lambda x:x['required_table']['materials'].reverse(),
            'wrong_column_heading':lambda x:x['required_table']['headers'].__setitem__(1,'Total price'),
            'wrong_table_value':lambda x:x['required_table']['cells'][0].__setitem__(0,999),
            'table_markup_omitted':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0].replace(table_markup(x['required_table']),'')),
            'duplicate_table':lambda x:x['sections'][0]['units'].__setitem__(0,x['sections'][0]['units'][0]+'\n\n'+table_markup(x['required_table'])),
            'wrong_fee_option_column':lambda x:x['fee_comparison']['option_cells']['A'].__setitem__(1,1-x['fee_comparison']['option_cells']['A'][1]),
            'wrong_fee_answer':lambda x:x['questions'][3].__setitem__('answer',next(k for k in 'ABCD'if k!=x['questions'][3]['answer'])),
            'lost_B_context_mark':lambda x:x['sections'][1]['units'].__setitem__(0,x['sections'][1]['units'][0].replace('**'+x['lexical_target']+'**',x['lexical_target'])),
            'old_source_wrong_paragraph2':lambda x:x.__setitem__('lexical_paragraph',2),
            'lost_C_metaphor_mark':lambda x:x['sections'][2]['units'].__setitem__(0,x['sections'][2]['units'][0].replace('**'+x['metaphor_target']+'**',x['metaphor_target'])),
            'wrong_closing_quote':lambda x:x.__setitem__('closing_quote','Words absent from this report'),
            'lost_qualified_scope':lambda x:x['research_scope'].__setitem__('limitations',''),
            'real_report_claim':lambda x:x.__setitem__('fictional_people_books_products_studies',False),
        };rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(d);mut(bad)
            try:validate(bad,b,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid draft accepted: '+name)
        for name,mut in {
            'source_missing_fee_requirement':lambda x:x['configuration'].__setitem__('required_tables',[]),
            'source_three_passages_claimed_as_four':lambda x:x['configuration'].__setitem__('passage_count',4),
            'source_missing_span':lambda x:x['source_spans'].pop(),
            'source_gold_promotion':lambda x:x.__setitem__('source_key_is_gold',True),
            'source_unreviewed_genre':lambda x:x.update(authors_genre_model_ready=False,genre_substructure_further_review_before_authoring=True),
        }.items():
            bad=copy.deepcopy(s);mut(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,ensure_ascii=False,sort_keys=True))
            try:validate(d,bb,bad)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        broken=copy.deepcopy(g);broken['passageHtml']=broken['passageHtml'].replace('</table>','</table><table><tr><td>extra</td></tr></table>',1)
        try:check(broken,a,b,s)
        except AssertionError:rejected.append('extra_rendered_table')
        else:raise AssertionError('Extra rendered table accepted')
        records.append(dict(id=m['id'],response_positions=15,candidate_positions=60,table_rows=3,table_numeric_columns=2,table_numeric_cells=6,complete_three_passage_contract_passed=True,negative_controls=rejected))
    assert records
    return dict(records=records,complete_groups=len(records),response_positions=sum(x['response_positions']for x in records),candidate_positions=sum(x['candidate_positions']for x in records),negative_controls=sum(len(x['negative_controls'])for x in records),not_independent_semantic_or_student_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.page)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
