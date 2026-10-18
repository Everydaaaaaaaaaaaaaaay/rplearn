#!/usr/bin/env python3
"""Check the next classified sections and explicit input overlays, not answer gold."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from bs4 import BeautifulSoup
from PIL import Image
from grade_mode_evidence import load_ref


def digest(text):return hashlib.sha256(text.encode()).hexdigest()


def validate_record(r):
    c=r['configuration'];spans=r['source_spans'];obs=r['source_observations']
    assert r['boundary_classified'] and r['full_body_and_all60candidate_rows_context_read']
    assert r['kind']=='reading_choice' and r['responses']==15 and r['options_each']==4
    assert c['response_distribution']==[3,4,4,4] and c['passage_count']==c['subgroup_count']==4
    assert c['responses']==15 and c['options_each']==4
    assert c['selected_objective_points']==15*c['points_each']
    assert c['all_selected_subgroups_mandatory'] and not c['shared_candidates']
    assert not c['necessary_audio'] and not c['required_tables'] and not c['required_lists']
    assert not r['source_key_is_gold'] and r['source_count_increment']==0
    assert not r['source_whole_paper_acquired'] and r['requires_new_source_bindings_and_group_contract_before_authoring']
    assert r['author_count']==0 and r['whole_original_target']==r['remaining_whole_originals']==3
    h=r['whole_objective_header'];raw=load_ref(h['source']).read_text()
    assert raw[h['start_offset']:h['end_offset']]==h['text']
    assert digest(h['text'])==h['sha256']
    selected_header=h['text'].split('第一节',1)[1]
    assert re.search(r'共\s*15\s*小题',selected_header)
    assert float(re.search(r'每小题\s*([\d.]+)\s*分',selected_header)[1])==c['points_each']
    assert float(re.search(r'满分\s*([\d.]+)\s*分',selected_header)[1])==c['selected_objective_points']
    assert len(spans)==len(obs)==len(c['subgroups'])==4
    assert c['text_unit_count']==sum(s['material_units']for s in c['subgroups'])
    previous=h['end_offset'];allnums=[];bodies={}
    for label,sp,o,sub,count in zip('ABCD',spans,obs,c['subgroups'],[3,4,4,4]):
        assert sp['label']==sub['label']==label and sp['source_member_id']==o['id']
        assert o['paper_id']==r['paper_id'] and o['shape']['grade']==r['level']
        assert o['shape']['responses']==sub['responses']==count
        assert o['shape']['options_each']==4 and sp['source']==o['source_text_ref']==h['source']
        assert not o['positive_answer_anchor_admitted'] and not o['production_supported']
        assert sp['material_unit_count']==sub['material_units']
        assert sp['start_offset']>=previous;previous=sp['end_offset']
        text=raw[sp['start_offset']:sp['end_offset']]
        assert text.startswith(label+'\n') and digest(text)==sp['sha256']
        assert sp['body_start_offset']==sp['start_offset']+2
        body=raw[sp['body_start_offset']:sp['body_end_offset']];bodies[label]=body
        assert body.strip() and digest(body)==sp['body_sha256']
        qs=list(re.finditer(r'(?m)^(\d+)\.(.*?)(?=^\d+\.|\Z)',raw[sp['body_end_offset']:sp['end_offset']],re.S))
        assert [int(q[1])for q in qs]==sp['question_numbers'] and len(qs)==count
        assert all(re.findall(r'(?:^|\s)([A-D])[.．]',q[2])==list('ABCD')for q in qs)
        allnums+=sp['question_numbers']
    assert allnums==list(range(allnums[0],allnums[0]+15))
    if 'shenzhen' in r['paper_id']:
        assert r['level']==10 and c['points_each']==2.5 and c['text_unit_count']==4
        assert c['necessary_images'] and c['required_images']==['A.labelled_curve_graph']
        assert r['source_full_inputs_verified']
        assert obs[0]['necessary_input_complete'] is False  # historical text remains unmodified
        overlay=r['necessary_input_overlay'];assert overlay['previous_member_flag_false_preserved']
        assert overlay['member_id']==obs[0]['id'] and overlay['raw_text_and_original_flags_not_overwritten']
        refs=overlay['new_visual_input_evidence'];assert len(refs)==2
        assert [Image.open(load_ref(ref)).size for ref in refs]==[(860,1216)]*2
        assert overlay['graph_preview_page_position']==3
        assert overlay['graph_answer_pointC_visible_at_catch_curve_peak']
        assert overlay['low_high_fishing_pressure_axis_visible']
        assert overlay['only_catch_curve_clearly_drawn_and_stock_label_floating_no_stock_line_inferred']
        assert overlay['numeric_stock_percent_not_read_from_plot']
        assert overlay['B_phrase_visible_in_preview4']
        assert overlay['B_unnamed_underlined_phrase']=='white-knuckling her way through'
        assert overlay['B_unnamed_underlined_phrase'] in bodies['B']
        crop=Image.open(load_ref(overlay['inspection_crop']))
        expected=Image.open(load_ref(refs[0])).crop(tuple(overlay['graph_box_pixels'])).resize((860,680))
        assert crop.size==expected.size and crop.tobytes()==expected.tobytes()
        assert 'Which point on the graph' in raw[spans[0]['body_end_offset']:spans[0]['end_offset']]
    elif 'yinchuan' in r['paper_id']:
        assert r['level']==11 and c['points_each']==2.5 and c['text_unit_count']==4
        assert r['source_full_inputs_verified'] and not c['necessary_images'] and not c['required_images']
        a=bodies['A'];heads=r['A_required_subheadings'];assert len(heads)==6
        assert [x['heading']for x in heads]==['Key duties','Schedule','Location','Qualifications','Compensation (待遇)','Work challenges']
        for i,x in enumerate(heads):
            block=a[x['relative_start']:x['relative_end']]
            assert block.startswith(x['heading']) and digest(block)==x['sha256']
            assert x['relative_end']==(heads[i+1]['relative_start']if i+1<len(heads)else len(a))
        f=r['qualification_fields'];assert f==dict(minimum_age21=True,licensed_driving_text='3+ years',license_endpoint_inclusive_not_over3=True,weekly_hours40=True,spring_days='Tuesday to Saturday',summer_days='Monday to Friday',weekly_pay750=True,pay_interval='every two weeks',preferred_experience_not_mandatory=True)
        for text in ['at least 21','3+ years','40 hours per week','Tuesday to Saturday','Monday to Friday','$750/week','every two weeks','Preferred skills']:assert text in a
    else:
        assert 'weishi' in r['paper_id'] and r['level']==10
        assert c['points_each']==2 and c['text_unit_count']==7
        assert [s['material_units']for s in c['subgroups']]==[4,1,1,1]
        assert not c['necessary_images'] and not c['required_images']
        assert not r['source_full_inputs_verified'] and obs[3]['necessary_input_complete'] is False
        assert r['last_available_public_preview5_ends_inside_C_questions_no_D']
        assert r['authoring_waits_for_symbol_input_or_another_verified_same_pattern_source']
        missing=r['missing_inputs'];assert len(missing)==1
        assert missing[0]['kind']=='chemical_subscript_typography' and missing[0]['do_not_guess_CO2_O2_N2']
        assert missing[0]['member_id']==obs[3]['id'] and missing[0]['text_as_seen']=='CO / O / N'
        assert 'They absorb CO  and produce O .' in bodies['D'] and 'changing N  in the atmosphere' in bodies['D']
        for ref in r['public_preview_inspected']:load_ref(ref)
    return True


def run(review_path):
    d=json.loads(review_path.read_text());records=d['records'];assert len(records)==3
    out=[]
    for r in records:
        validate_record(r);cases={
            'only_A_selected':lambda x:x['source_spans'].__delitem__(slice(1,None)),
            'D_missing':lambda x:x['source_spans'].pop(),
            'six_response_clip':lambda x:x['configuration'].__setitem__('responses',6),
            'wrong_count_distribution':lambda x:x['configuration'].__setitem__('response_distribution',[3,3,4,5]),
            'wrong_grade':lambda x:x.__setitem__('level',9),
            'wrong_parent':lambda x:x['source_observations'][1].__setitem__('paper_id','other'),
            'wrong_option_count':lambda x:x['source_observations'][1]['shape'].__setitem__('options_each',3),
            'wrong_header_SHA':lambda x:x['whole_objective_header'].__setitem__('sha256','0'*64),
            'wrong_body_SHA':lambda x:x['source_spans'][1].__setitem__('body_sha256','0'*64),
            'wrong_point_allocation':lambda x:x['configuration'].__setitem__('points_each',1),
            'wrong_total_score':lambda x:x['configuration'].__setitem__('selected_objective_points',50),
            'optional_ABCD_invented':lambda x:x['configuration'].__setitem__('all_selected_subgroups_mandatory',False),
            'original_key_gold_upgrade':lambda x:x.__setitem__('source_key_is_gold',True),
            'new_parent_count_invented':lambda x:x.__setitem__('source_count_increment',1),
            'full_paper_upgrade':lambda x:x.__setitem__('source_whole_paper_acquired',True),
            'new_authors_invented':lambda x:x.__setitem__('author_count',3),
        }
        if 'shenzhen' in r['paper_id']:
            cases.update({
                'graph_not_necessary':lambda x:x['configuration'].__setitem__('necessary_images',False),
                'graph_asset_missing':lambda x:x['necessary_input_overlay']['new_visual_input_evidence'].pop(),
                'graph_asset_SHA_drift':lambda x:x['necessary_input_overlay']['new_visual_input_evidence'][0].__setitem__('sha256','0'*64),
                'original_false_flag_overwritten':lambda x:x['source_observations'][0].__setitem__('necessary_input_complete',True),
                'graph_C_not_visible':lambda x:x['necessary_input_overlay'].__setitem__('graph_answer_pointC_visible_at_catch_curve_peak',False),
                'stock_line_invented':lambda x:x['necessary_input_overlay'].__setitem__('only_catch_curve_clearly_drawn_and_stock_label_floating_no_stock_line_inferred',False),
                'B_phrase_truncated':lambda x:x['necessary_input_overlay'].__setitem__('B_unnamed_underlined_phrase','white-knuckling'),
                'wrong_crop_region':lambda x:x['necessary_input_overlay'].__setitem__('graph_box_pixels',[0,0,100,100]),
            })
        elif 'yinchuan' in r['paper_id']:
            cases.update({
                'sixth_advert_block_lost':lambda x:x['A_required_subheadings'].pop(),
                'advert_block_SHA_wrong':lambda x:x['A_required_subheadings'][3].__setitem__('sha256','0'*64),
                'inclusive_endpoint_excluded':lambda x:x['qualification_fields'].__setitem__('license_endpoint_inclusive_not_over3',False),
                'preferred_as_mandatory':lambda x:x['qualification_fields'].__setitem__('preferred_experience_not_mandatory',False),
                'spring_and_summer_days_merged':lambda x:x['qualification_fields'].__setitem__('spring_days','Monday to Friday'),
                'fortnightly_pay_as_monthly':lambda x:x['qualification_fields'].__setitem__('pay_interval','monthly'),
            })
        else:
            cases.update({
                'missing_symbols_promoted_complete':lambda x:x.__setitem__('source_full_inputs_verified',True),
                'symbol_missing_record_removed':lambda x:x['missing_inputs'].clear(),
                'symbols_guessed_from_chemistry':lambda x:x['missing_inputs'][0].__setitem__('do_not_guess_CO2_O2_N2',False),
                'preview5_claimed_contains_D':lambda x:x.__setitem__('last_available_public_preview5_ends_inside_C_questions_no_D',False),
                'four_profiles_flattened_to_one':lambda x:x['configuration']['subgroups'][0].__setitem__('material_units',1),
                'input_gap_skipped_for_authoring':lambda x:x.__setitem__('authoring_waits_for_symbol_input_or_another_verified_same_pattern_source',False),
            })
        rejected=[]
        for name,mut in cases.items():
            bad=copy.deepcopy(r);mut(bad)
            try:validate_record(bad)
            except (AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid boundary accepted: '+name)
        out.append(dict(id=r['id'],member_records=4,responses=15,candidates=60,source_full_inputs=r['source_full_inputs_verified'],negative_controls=rejected))
    return dict(records=out,classified_member_records=12,full_input_member_records=8,incomplete_section_member_records=4,negative_controls=sum(len(r['negative_controls'])for r in out),new_original_groups=0,new_structure_records=0,not_source_key_or_real_fact_or_student_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.review)
    if a.report.exists():raise ValueError('Frozen proof must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items()if k!='records'}))
