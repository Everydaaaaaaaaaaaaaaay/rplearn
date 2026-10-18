#!/usr/bin/env python3
"""Verify native-page reading boundaries without upgrading printed keys to gold."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import load_ref


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def project(pages):
    text='\n'.join(pages)
    text=re.sub(r'(?m)^\s*第\d+页/共\d+页\s*$', '',text)
    text=re.sub(r'(?m)^ *([ABCD]) *$',r'\1',text)
    text='\n'.join(line.rstrip()for line in text.splitlines())
    text=text[re.search(r'第二部分[：:]\s*阅读理解',text).start():]
    stop=text.find('第二节')
    return (text[:stop]if stop>=0 else text).strip()+'\n'


def validate(r,prior,acquisitions):
    assert r['kind']=='reading_choice' and r['responses']==14 and r['options_each']==4
    assert r['source_full_inputs_verified'] and not r['source_key_is_gold']
    assert not r['source_key_and_factual_validation_independent']
    assert not r['independent_teacher_student_rights_production_validated']
    assert r['source_count_increment']==r['new_author_groups']==0
    assert r['full_body_and_all56candidate_rows_context_read']
    assert r['original_input_unknown_flags_retained']
    assert r['requires_native_projection_source_binding_and_whole14_author_contract']
    assert not r['authors_genre_model_ready'] and r['genre_substructure_further_review_before_authoring']
    parent=acquisitions[r['paper_id']]
    assert r['source_original_parent']==dict(path=parent['path'],sha256=parent['sha256'])
    load_ref(r['source_original_parent'])
    p=r['source_native_projection'];native=json.loads(load_ref(p['snapshot']).read_text())['native_source_pages_private'][r['paper_id']]
    assert p['parent_id']==r['paper_id']
    assert p['transform']=='remove exact printed page-number lines;normalize standalone A-D labels;strip line trailing whitespace;select reading first section only;no words or keys repaired'
    assert r['source_cover_as_seen']==native['1'].splitlines()[:15]
    assert ('高一'if r['level']==10 else'高二') in native['1']
    assert r['cover_and_footer_page_count_conflicts_preserved']
    numbers=[x['PDF_page']for x in p['pages']]
    assert numbers==list(range(2,6 if r['level']==10 else 8))
    values=[]
    for page in p['pages']:
        assert page['pointer']==['native_source_pages_private',r['paper_id'],str(page['PDF_page'])]
        text=native[str(page['PDF_page'])];assert digest(text)==page['sha256'];values.append(text)
    raw=load_ref(p['projection']).read_text();assert raw==project(values)
    c=r['configuration'];assert c['passage_count']==c['subgroup_count']==c['text_unit_count']==4
    assert c['response_distribution']==[3,4,3,4] and c['responses']==14
    assert c['points_each']==2 and c['selected_objective_points']==28 and c['whole_reading_points38_not_selected28']
    assert c['all_selected_subgroups_mandatory'] and not c['shared_candidates']
    assert not c['necessary_audio'] and not c['necessary_images'] and not c['required_images']
    h=r['whole_objective_header'];selected=r['selected_objective_header']
    for span in [h,selected]:
        assert span['source']==p['projection']
        text=raw[span['start_offset']:span['end_offset']]
        assert text==span['text'] and digest(text)==span['sha256']
    assert h['start_offset']==0 and re.search(r'共两节[，,]\s*38\s*分',h['text'])
    assert selected['text'].startswith('第一节') and selected['end_offset']==h['end_offset']
    assert re.search(r'共\s*14\s*小题',selected['text']) and re.search(r'每小题\s*2\s*分',selected['text'])
    assert re.search(r'共\s*28\s*分',selected['text'])
    existing=[x for x in prior['unreviewed_records']if x['paper_id']==r['paper_id']]
    assert r['existing_catalogue_observations']==existing
    assert len(r['source_spans'])==len(r['source_observations'])==len(c['subgroups'])==4
    obs={o['id']:o for o in r['source_observations']}
    assert all(obs[o['id']]==o for o in existing)
    assert len(r['supplementary_whole_parent_observations'])+len(existing)==4
    assert all(obs[o['id']]==o and o['shape']['details']['not_in_inherited_selected127'] for o in r['supplementary_whole_parent_observations'])
    cursor=h['end_offset'];question_numbers=[];bodies={}
    for i,(sp,ob,sub)in enumerate(zip(r['source_spans'],r['source_observations'],c['subgroups'])):
        label='ABCD'[i];assert sp['label']==sub['label']==label
        assert sp['source']==p['projection'] and sp['source_member_id']==ob['id']
        assert sp['start_offset']==cursor;cursor=sp['end_offset']
        whole=raw[sp['start_offset']:sp['end_offset']]
        assert whole.startswith(label+'\n') and digest(whole)==sp['sha256']
        assert sp['body_start_offset']==sp['start_offset']+2
        body=raw[sp['body_start_offset']:sp['body_end_offset']];bodies[label]=body
        assert digest(body)==sp['body_sha256'] and sp['material_unit_count']==sub['material_units']==1
        assert ob['shape']['grade']==r['level'] and ob['shape']['family']=='reading_choice'
        assert ob['shape']['responses']==sub['responses']==c['response_distribution'][i]
        assert ob['paper_id']==r['paper_id'] and ob['necessary_input_complete'] is None
        assert not ob['positive_answer_anchor_admitted'] and not ob['production_supported']
        qs=list(re.finditer(r'(?m)^(\d+)\.(.*?)(?=^\d+\.|\Z)',raw[sp['body_end_offset']:sp['end_offset']],re.S))
        assert [int(q[1])for q in qs]==sp['question_numbers'] and len(qs)==sub['responses']
        assert all(re.findall(r'(?:^|\s)([A-D])\.',q[2])==list('ABCD')for q in qs)
        question_numbers+=sp['question_numbers']
    assert cursor==len(raw) and question_numbers==list(range(21,35))
    assert [x['PDF_page']for x in r['visually_inspected_pages']]==numbers
    for page in r['visually_inspected_pages']:load_ref(page['render'])
    for target in r['lexical_target_spans']:
        span=r['source_spans']['ABCD'.index(target['part'])]
        assert span['body_start_offset']<=target['start_offset']<target['end_offset']<=span['body_end_offset']
        literal=raw[target['start_offset']:target['end_offset']]
        assert literal==target['target_literal'] and digest(literal)==target['sha256']
        assert ' '.join(literal.split())==target['whitespace_normalized'] and target['underline_seen_in_original_render']
    assert [t['whitespace_normalized']for t in r['lexical_target_spans']]==(['Money with no strings attached','mind’s eye']if r['level']==10 else['eliminating'])
    key=r['source_keys'];assert key['snapshot']==p['snapshot'] and not key['independent_gold']
    for page in key['pages']:
        assert page['pointer']==['native_source_pages_private',r['paper_id'],str(page['PDF_page'])]
        assert digest(native[str(page['PDF_page'])])==page['sha256']
    if r['level']==10:
        expected=[dict(number=int(n),published_answer=a)for n,a in re.findall(r'(\d+)[．.]\s*([A-D])',native['8'])if 21<=int(n)<=34]
        assert not c['required_lists'] and not c['illustrative_images']
        assert not r['illustrative_source_media'] and not r['A_bullet_sections']
    else:
        expected=[]
        for n in [13,14,15]:
            for line in re.findall(r'【答案】([^\n]+)',native[str(n)]):
                expected +=[dict(number=int(k),published_answer=a)for k,a in re.findall(r'(\d+)\.\s*([A-D])',line)if 21<=int(k)<=34]
        assert c['required_lists']==['A.benefits_requirements_and_service_bullet_lists']
        assert [b['heading']for b in r['A_bullet_sections']]==['Why volunteer with the UN','Requirements','Conditions of Service']
        for block in r['A_bullet_sections']:
            text=bodies['A'][block['relative_start']:block['relative_end']]
            assert text.startswith(block['heading'])and digest(text)==block['sha256']
            assert len(re.findall(r'(?m)^•',text))==block['bullet_count']==len(block['bullet_spans'])==4
            for bullet in block['bullet_spans']:
                text=bodies['A'][bullet['relative_start']:bullet['relative_end']]
                assert text.startswith('•')and digest(text)==bullet['sha256']
        assert r['authoring_requires_explicit_illustrative_media_handling_not_silent_drop']
        media=r['illustrative_source_media'];assert c['illustrative_images']==[m['id']for m in media]
        assert [m['part']for m in media]==['B','C'] and [m['caption']for m in media]==['Williams and a few of her books','guineafowl']
        assert r['photo_caption_English_words_separate']==8
        for m in media:
            assert m['caption_visual_not_in_native_text'] and not m['required_for_unique_answer'] and m['reason']
            assert m['render']==next(p['render']for p in r['visually_inspected_pages']if p['PDF_page']==m['PDF_page'])
        assert 'strangers started leaving piles of books on her front porch' in bodies['B']
        assert 'friends to donate books or money to buy books' in bodies['B']
    assert key['items']==expected and len(expected)==14
    return True


def run(path):
    doc=json.loads(path.read_text());prior=json.loads(load_ref(doc['previous_reconciliation']).read_text())
    acquisitions={x['id']:x for x in json.loads((Path(__file__).resolve().parents[1]/'Registry/acquisitions.json').read_text())['acquisitions']}
    results=[]
    for r in doc['records']:
        validate(r,prior,acquisitions)
        cases={
            'only_first_passage':lambda x:x['source_spans'].__delitem__(slice(1,None)),
            'false_fourteen_distribution':lambda x:x['configuration'].__setitem__('response_distribution',[3,4,4,3]),
            'source_gold_upgrade':lambda x:x.__setitem__('source_key_is_gold',True),
            'missing_input_upgrade':lambda x:x.__setitem__('source_full_inputs_verified',False),
            'wrong_selected_points':lambda x:x['configuration'].__setitem__('selected_objective_points',38),
            'whole38_as_selected28':lambda x:x.__setitem__('selected_objective_header',x['whole_objective_header']),
            'old_unknown_overwritten':lambda x:x['source_observations'][0].__setitem__('necessary_input_complete',True),
            'supplementary_as_inherited':lambda x:x['supplementary_whole_parent_observations'][0]['shape']['details'].__setitem__('not_in_inherited_selected127',False),
            'native_page_SHA_wrong':lambda x:x['source_native_projection']['pages'][0].__setitem__('sha256','0'*64),
            'body_SHA_wrong':lambda x:x['source_spans'][0].__setitem__('body_sha256','0'*64),
            'one_response_missing':lambda x:x['source_spans'][1]['question_numbers'].pop(),
            'last_source_page_dropped':lambda x:x['source_native_projection']['pages'].pop(),
            'lexical_target_shortened':lambda x:x['lexical_target_spans'][0].__setitem__('whitespace_normalized','partial'),
            'underlining_not_checked':lambda x:x['lexical_target_spans'][0].__setitem__('underline_seen_in_original_render',False),
            'published_key_silently_repaired':lambda x:x['source_keys']['items'][5].__setitem__('published_answer','D'if x['source_keys']['items'][5]['published_answer']!='D'else'A'),
            'key_gold_upgrade':lambda x:x['source_keys'].__setitem__('independent_gold',True),
            'teacher_validation_upgrade':lambda x:x.__setitem__('independent_teacher_student_rights_production_validated',True),
            'author_gate_skipped':lambda x:x.__setitem__('authors_genre_model_ready',True),
        }
        if r['level']==11:
            cases.update({'bullet_section_missing':lambda x:x['A_bullet_sections'].pop(),
                          'twelfth_bullet_missing':lambda x:x['A_bullet_sections'][-1]['bullet_spans'].pop(),
                          'required_list_dropped':lambda x:x['configuration'].__setitem__('required_lists',[]),
                          'illustrative_picture_dropped':lambda x:x['illustrative_source_media'].pop(),
                          'caption_changed':lambda x:x['illustrative_source_media'][1].__setitem__('caption','unknown'),
                          'media_handling_skipped':lambda x:x.__setitem__('authoring_requires_explicit_illustrative_media_handling_not_silent_drop',False)})
        rejected=[]
        for name,fn in cases.items():
            bad=copy.deepcopy(r);fn(bad)
            try:validate(bad,prior,acquisitions)
            except(AssertionError,KeyError,IndexError,ValueError):rejected.append(name)
            else:raise AssertionError('Invalid reading boundary admitted: '+name)
        results.append(dict(id=r['id'],grade=r['level'],selected_existing_records=len(r['existing_catalogue_observations']),supplementary_not_in_inherited127=len(r['supplementary_whole_parent_observations']),responses=14,candidate_positions=56,distribution=[3,4,3,4],points28_not38=True,body_words=r['body_word_count'],negative_controls=rejected,source_key_not_gold=True,author_gate_not_yet_ready=True))
    return dict(records=results,source_sections=len(results),source_responses=sum(r['responses']for r in results),candidate_positions=sum(r['candidate_positions']for r in results),negative_controls=sum(len(r['negative_controls'])for r in results),new_inherited_structures=0,new_authors=0,not_independent_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.review)
    if a.report.exists():raise ValueError('Frozen report must not be overwritten')
    a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
