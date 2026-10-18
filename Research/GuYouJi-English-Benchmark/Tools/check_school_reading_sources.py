#!/usr/bin/env python3
"""Verify source-bound whole senior reading sections before compiling authors."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import load_ref


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def validate(source,binding):
    assert binding['source_record_sha256']==digest(json.dumps(source,ensure_ascii=False,sort_keys=True))
    assert source['id']==binding['source_group_id']
    assert source['level']==binding['level'] and source['kind']==binding['family']=='reading_choice'
    assert source['responses']==binding['responses'] and source['options_each']==binding['options_each']==4
    assert source['source_full_inputs_verified'] and not source['source_key_is_gold']
    assert source['source_count_increment']==binding['new_source_count']==0
    c=source['configuration'];h=source['whole_objective_header'];raw=load_ref(h['source']).read_text()
    header=raw[h['start_offset']:h['end_offset']]
    assert header==h['text'] and digest(header)==h['sha256']
    assert '阅读下列短文' in header and '任选' not in header
    assert int(re.search(r'共\s*(\d+)\s*小题',header)[1])==source['responses']
    assert float(re.search(r'每小题\s*([0-9.]+)\s*分',header)[1])==c['points_each']
    assert float(re.search(r'满分\s*([0-9.]+)\s*分',header)[1])==c['selected_objective_points']
    assert source['responses']*c['points_each']==c['selected_objective_points']
    assert c['all_selected_subgroups_mandatory'] and not c['shared_candidates']
    assert not c['necessary_audio'] and not c['necessary_images']
    assert c['subgroup_count']==c['passage_count']==len(c['subgroups'])
    assert c['response_distribution']==[s['responses']for s in c['subgroups']]
    assert sum(c['response_distribution'])==source['responses']
    assert c['text_unit_count']==sum(s['material_units']for s in c['subgroups'])
    assert len(source['source_spans'])==len(source['source_observations'])==c['passage_count']
    previous_end=h['end_offset'];numbers=[];bodies={}
    for i,(sp,ob,sub)in enumerate(zip(source['source_spans'],source['source_observations'],c['subgroups'])):
        assert sp['label']==sub['label']=='ABCD'[i]
        assert sp['source']==ob['source_text_ref']==h['source']
        assert sp['source_member_id']==ob['id']
        assert ob['paper_id']==source['source_observations'][0]['paper_id']
        assert ob['shape']['grade']==source['level'] and ob['shape']['family']=='reading_choice'
        assert ob['shape']['responses']==sub['responses']==len(sp['question_numbers'])
        assert ob['shape']['options_each']==4 and ob['necessary_input_complete'] is True
        assert sp['start_offset']>=previous_end;previous_end=sp['end_offset']
        selected=raw[sp['start_offset']:sp['end_offset']]
        assert selected.startswith(sp['label']+'\n') and digest(selected)==sp['sha256']
        assert sp['body_start_offset']==sp['start_offset']+2
        body=raw[sp['body_start_offset']:sp['body_end_offset']];bodies[sp['label']]=body
        assert digest(body)==sp['body_sha256'] and sp['material_unit_count']==sub['material_units']
        qtext=raw[sp['body_end_offset']:sp['end_offset']]
        qs=list(re.finditer(r'(?m)^(\d+)(?:\.|\s)+(.*?)(?=^\d+(?:\.|\s)|\Z)',qtext,re.S))
        assert [int(q[1])for q in qs]==sp['question_numbers']
        assert all(re.findall(r'(?:^|\s)([A-D])\.',q[2])==list('ABCD')for q in qs)
        numbers+=sp['question_numbers']
    assert numbers==list(range(numbers[0],numbers[0]+source['responses']))
    if source.get('source_A_book_entries'):
        assert c['subgroups'][0]['material_units']==len(source['source_A_book_entries'])==4
        cursor=len(source['source_A_intro']);assert bodies['A'].startswith(source['source_A_intro'])
        for entry in source['source_A_book_entries']:
            assert entry['relative_start']==cursor
            text=bodies['A'][cursor:entry['relative_end']]
            assert text.startswith(entry['title']) and digest(text)==entry['sha256']
            cursor=entry['relative_end']
        assert cursor==len(bodies['A'])
    if source.get('program_profile_entry_spans_bound'):
        assert c['subgroups'][0]['genre']=='four_family_program_profiles'
        assert c['subgroups'][0]['material_units']==len(source['source_A_program_entries'])==4
        intro=source['source_A_program_intro'];cursor=intro['relative_end']
        assert digest(bodies['A'][:cursor])==intro['sha256']
        for entry in source['source_A_program_entries']:
            assert entry['relative_start']==cursor
            text=bodies['A'][cursor:entry['relative_end']]
            assert text.startswith(entry['title']+'\n') and digest(text)==entry['sha256']
            cursor=entry['relative_end']
        assert cursor==len(bodies['A'])
    if source.get('credit_requirement_blocks_bound'):
        assert 'A.credit_requirements' in c['required_lists']
        blocks=source['source_A_requirement_blocks'];assert len(blocks)==5
        assert source['raw_A197_words_undersegmented_not_grade_limit']
        for i,block in enumerate(blocks):
            selected=bodies['A'][block['relative_start']:block['relative_end']]
            assert selected.startswith(block['heading']) and digest(selected)==block['sha256']
            assert block['relative_end']==(blocks[i+1]['relative_start']if i+1<len(blocks)else len(bodies['A']))
    if 'Interlibrary Loan Fees' in bodies['A']:
        assert c['required_tables']==['A.fee_table']
        assert re.findall(r'(?m)^(Non-Profit Libraries|For-Profit Libraries|International Libraries)\s+\$(\d+)\s+\$(\d+)',bodies['A'])==[
            ('Non-Profit Libraries','15','10'),('For-Profit Libraries','20','12'),('International Libraries','25','15')]
    if 'Compulsory' in bodies['A'] and 'Optional credits' in bodies['A']:
        assert 'A.credit_requirements' in c['required_lists']
    if re.search(r'(?m)^Step\s+1\s',bodies['A']):
        assert 'A.numbered_advice_steps' in c['required_lists']
        assert c['subgroups'][0]['genre']=='advice_article_with_steps'
    assert source['authors_genre_model_ready'] != source['genre_substructure_further_review_before_authoring']
    return True


def run(bindings_path):
    doc=json.loads(bindings_path.read_text());result=[]
    for b in doc['bindings']:
        s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==b['source_group_id'])
        validate(s,b);cases={
            'source_promoted_to_gold':lambda x:x.__setitem__('source_key_is_gold',True),
            'source_input_missing':lambda x:x.__setitem__('source_full_inputs_verified',False),
            'one_passage_missing':lambda x:x['source_spans'].pop(),
            'only_first_passage':lambda x:x['source_spans'].__delitem__(slice(1,None)),
            'wrong_point_allocation':lambda x:x['configuration'].__setitem__('points_each',99),
            'wrong_total_points':lambda x:x['configuration'].__setitem__('selected_objective_points',99),
            'wrong_header_SHA':lambda x:x['whole_objective_header'].__setitem__('sha256','0'*64),
            'wrong_body_SHA':lambda x:x['source_spans'][0].__setitem__('body_sha256','0'*64),
            'different_parent':lambda x:x['source_observations'][1].__setitem__('paper_id','other-paper'),
            'invented_optional_materials':lambda x:x['configuration'].__setitem__('all_selected_subgroups_mandatory',False),
            'flattened_count_distribution':lambda x:x['configuration'].__setitem__('response_distribution',[s['responses']]),
        }
        if s.get('source_A_book_entries'):
            cases['missing_fourth_book']=lambda x:x['source_A_book_entries'].pop()
        if s.get('program_profile_entry_spans_bound'):
            cases['missing_fourth_program']=lambda x:x['source_A_program_entries'].pop()
            cases['wrong_program_intro_SHA']=lambda x:x['source_A_program_intro'].__setitem__('sha256','0'*64)
        if s.get('credit_requirement_blocks_bound'):
            cases['missing_credit_block']=lambda x:x['source_A_requirement_blocks'].pop()
            cases['wrong_credit_block_SHA']=lambda x:x['source_A_requirement_blocks'][0].__setitem__('sha256','0'*64)
        if s['configuration']['required_tables']:
            cases['mandatory_fee_table_omitted']=lambda x:x['configuration'].__setitem__('required_tables',[])
        if s['configuration']['required_lists']:
            cases['mandatory_list_omitted']=lambda x:x['configuration'].__setitem__('required_lists',[])
        rejected=[]
        for name,mutate in cases.items():
            bad=copy.deepcopy(s);mutate(bad);bb=copy.deepcopy(b);bb['source_record_sha256']=digest(json.dumps(bad,ensure_ascii=False,sort_keys=True))
            try:validate(bad,bb)
            except (AssertionError,IndexError,KeyError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        result.append(dict(id=s['id'],grade=s['level'],passages=s['configuration']['passage_count'],responses=s['configuration']['response_distribution'],points_each=s['configuration']['points_each'],source_spans_checked=len(s['source_spans']),negative_controls=rejected,author_genre_model_ready=s['authors_genre_model_ready']))
    return dict(records=result,complete_section_sources=len(result),source_member_records=sum(r['source_spans_checked']for r in result),negative_controls=sum(len(r['negative_controls'])for r in result),new_source_downloads=0,not_answer_gold_or_independent_fact_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bindings',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.bindings)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
