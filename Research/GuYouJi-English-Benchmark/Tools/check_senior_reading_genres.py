#!/usr/bin/env python3
"""Bind reviewed genre substructures and source-dependent nested inputs."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import load_ref


def sha(t):return hashlib.sha256(t.encode()).hexdigest()


def validate(row,s):
    assert row['id']==s['id'] and row['grade']==s['level']
    assert row['full_body_and_all_questions_context_read'] and row['genre_model_ready']
    assert not row['source_facts_keys_and_authentication_gold']
    assert s['authors_genre_model_ready'] and not s['genre_substructure_further_review_before_authoring']
    assert len(row['passages'])==len(s['source_spans']) and len(row['author_requirements'])==len(s['source_spans'])
    bodies={}
    for p,sp in zip(row['passages'],s['source_spans']):
        assert p['source']==sp['source'] and p['label']==sp['label']
        assert p['start_offset']==sp['body_start_offset'] and p['end_offset']==sp['body_end_offset']
        raw=load_ref(p['source']).read_text();body=raw[p['start_offset']:p['end_offset']];bodies[p['label']]=body
        assert p['body_sha256']==sp['body_sha256']==sha(body)
        assert p['source_response_numbers']==sp['question_numbers']
        assert len(p['source_cognitive_operations'])==len(sp['question_numbers'])
        assert p['genre_substructure'] and p['all_option_rows_read'] and p['not_a_required_exhaustive_cognitive_distribution']
    if s['configuration']['subgroups'][0]['genre']=='four_family_program_profiles':
        assert len(row['A_four_program_entries'])==4
        body=bodies['A'];cursor=row['A_intro_relative_end'];assert sha(body[:cursor])==row['A_intro_sha256']
        for x in row['A_four_program_entries']:
            assert x['relative_start']==cursor;text=body[cursor:x['relative_end']]
            assert text.startswith(x['title']+'\n') and sha(text)==x['sha256'];cursor=x['relative_end']
        assert cursor==len(body)
    if s['configuration']['required_tables']:
        t=row['required_table'];assert t['id']=='A.fee_table' and len(t['column_meanings'])==2
        actual=re.findall(r'(?m)^(Non-Profit Libraries|For-Profit Libraries|International Libraries)\s+\$(\d+)\s+\$(\d+)',bodies['A'])
        assert t['row_labels']==[x[0]for x in actual]
        assert t['cells']==[[int(x[1]),int(x[2])]for x in actual]
        assert t['Q54_candidate_costs_in_source_order']==[t['cells'][0][1],t['cells'][2][1],t['cells'][1][0],t['cells'][0][0]]
        assert max(t['Q54_candidate_costs_in_source_order'])==20 and max(v for row in t['cells']for v in row)==25
        assert t['Q54_highest_offered_cost20_not_highest_whole_table25']
    if 'A.credit_requirements' in s['configuration']['required_lists']:
        blocks=row['A_requirement_blocks'];assert len(blocks)==5
        for i,x in enumerate(blocks):
            assert bodies['A'][x['relative_start']:x['relative_end']].startswith(x['heading'])
            assert x['relative_end']==(blocks[i+1]['relative_start']if i+1<len(blocks)else len(bodies['A']))
        assert row['raw197_word_count_not_normal_segmentation']
    if 'A.numbered_advice_steps' in s['configuration']['required_lists']:
        assert len(row['A_numbered_step_headings'])==4
        assert row['A_numbered_step_headings']==re.findall(r'(?m)^Step [1-4] .+',bodies['A'])
    return True


def run(review_path,source_path):
    review=json.loads(review_path.read_text());sources=json.loads(source_path.read_text());result=[]
    for row in review['records']:
        s=next(x for x in sources['groups']if x['id']==row['id']);validate(row,s)
        cases={
            'lost_passage':lambda x:x['passages'].pop(),
            'wrong_body_SHA':lambda x:x['passages'][0].__setitem__('body_sha256','0'*64),
            'source_promoted_gold':lambda x:x.__setitem__('source_facts_keys_and_authentication_gold',True),
            'lost_author_requirement':lambda x:x['author_requirements'].pop(),
            'unread_question_rows':lambda x:x['passages'][0].__setitem__('all_option_rows_read',False),
            'wrong_source_response_range':lambda x:x['passages'][0]['source_response_numbers'].pop(),
        }
        if row.get('A_four_program_entries'):cases['missing_program_profile']=lambda x:x['A_four_program_entries'].pop()
        if row.get('required_table'):
            cases['missing_fee_row']=lambda x:x['required_table']['cells'].pop()
            cases['wrong_fee_cell']=lambda x:x['required_table']['cells'][0].__setitem__(0,25)
            cases['highest_whole_table_as_candidate_key']=lambda x:x['required_table']['Q54_candidate_costs_in_source_order'].__setitem__(2,25)
        if row.get('A_requirement_blocks'):cases['missing_online_credit_block']=lambda x:x['A_requirement_blocks'].pop(2)
        if row.get('A_numbered_step_headings'):cases['missing_advice_step']=lambda x:x['A_numbered_step_headings'].pop()
        rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(row);mut(bad)
            try:validate(bad,s)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid genre input accepted: '+name)
        result.append(dict(id=row['id'],full_passages=len(row['passages']),source_responses=sum(len(p['source_response_numbers'])for p in row['passages']),negative_controls=rejected))
    return dict(records=result,configurations=len(result),full_passages=sum(r['full_passages']for r in result),source_responses=sum(r['source_responses']for r in result),negative_controls=sum(len(r['negative_controls'])for r in result),source_keys_facts_authentication_not_gold=True,new_authored_groups=0)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--sources',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.review,a.sources)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
