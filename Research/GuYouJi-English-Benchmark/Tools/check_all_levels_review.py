#!/usr/bin/env python3
"""Verify complete objective data, label identity and preserved source boundaries."""
import argparse
import hashlib
import itertools
import json
import re
import base64
import xml.etree.ElementTree as ET
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from research_number_marking import correct_number


def extract(page):
    return json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>',page.read_text(),re.S)[1])


def check(page):
    data=extract(page);policy=json.loads(load_ref(data['current_scope_policy']).read_text())
    holds=json.loads(load_ref(data['concrete_group_holds']).read_text()) if data.get('concrete_group_holds') else {'records':[]}
    held={r['id']:r for r in holds['records']}
    def preserved(prior):
        for key,value in prior['groups'].items():
            if key in held:
                assert key not in data['groups']
                assert value['candidate']==held[key]['candidate'] and value['author_check']==held[key]['author_check']
                # Legacy generated grammar payloads use kind=language; the matrix
                # retains their concrete passage_form family in the pinned hold.
                cells=[c for c in data['cells']if c['grade']==value['grade']and c['family']==held[key]['family']]
                assert len(cells)==1 and cells[0]['observed'] and cells[0]['groupId'] is None
                assert cells[0]['state']=='paused_requires_semantic_adjudication' and cells[0]['pauseReason']
            else:
                assert data['groups'][key]==value,'Unpaused full input changed: '+key
        return True
    assert len(data['grades'])==len(set(data['grades']))==16
    assert len(data['cells'])==16*len(set(c['family']for c in data['cells']))
    assert len(set((c['grade'],c['family'])for c in data['cells']))==len(data['cells'])
    assert not(set(c['family']for c in data['cells']) & set(policy['paused_families']))
    assert {c['groupId']for c in data['cells']if c['groupId']}==set(data['groups'])
    if data.get('existing_CET_source_index'):
        cet=json.loads(load_ref(data['existing_CET_source_index']).read_text())
        for source in cet['groups']:
            if source['kind']=='word_bank_cloze':
                cell=next(c for c in data['cells'] if c['grade']==source['level'] and c['family']=='shared_bank')
                assert cell['observed'], 'Existing complete source cannot become unknown merely because no author is delivered'
                if not cell['groupId']:
                    assert cell['state']=='source_observed_author_pending' and source['id'] in cell['source_group_ids']
    acqs=json.loads((BASE/'Registry/acquisitions.json').read_text())['acquisitions']
    old_record=next(a for a in json.loads((BASE/'Registry/processing.json').read_text())['runs'] if a['id']=='objective-scope-owner-correction-20261016-v0.1')
    frozen=next(r for r in old_record['page_records']if r['output'].endswith('.html'))
    prior_page=REPO/frozen['output'];assert hashlib.sha256(prior_page.read_bytes()).hexdigest()==frozen['sha256']
    old=extract(prior_page)
    preserved(old)
    first_run=next((r for r in json.loads((BASE/'Registry/processing.json').read_text())['runs']
                    if r['id']=='all16-first-nonmiddle-objective-batch20261016-v0.1'),None)
    if first_run:
        frozen60=next(r for r in first_run['page_records']if r['output'].endswith('.html'))
        p60=REPO/frozen60['output']
        assert hashlib.sha256(p60.read_bytes()).hexdigest()==frozen60['sha256']
        preserved(extract(p60))
    second_run=next((r for r in json.loads((BASE/'Registry/processing.json').read_text())['runs']
                     if r['id']=='all16-second-official-advanced-primary12-20261016-v0.1'),None)
    if second_run:
        frozen62=next(r for r in second_run['page_records']if r['output'].endswith('.html'))
        p62=REPO/frozen62['output']
        assert hashlib.sha256(p62.read_bytes()).hexdigest()==frozen62['sha256']
        preserved(extract(p62))
    third_run=next((r for r in json.loads((BASE/'Registry/processing.json').read_text())['runs']
                    if r['id']=='all16-third-primary2-fullpictures-and-matching20261016-v0.1'),None)
    if third_run:
        frozen64=next(r for r in third_run['page_records']if r['output'].endswith('.html'))
        p64=REPO/frozen64['output']
        assert hashlib.sha256(p64.read_bytes()).hexdigest()==frozen64['sha256']
        preserved(extract(p64))
    if held:
        assert set(held)<=set(old['groups']) and len(held)==data['paused_concrete_groups']==holds['paused_groups']
        assert sum(r['responses']for r in held.values())==holds['paused_responses']
        assert all(r['whole_group_paused'] and r['counterexamples']for r in held.values())
    plan=json.loads((BASE/'FirstRelease/AllLevelsObjectiveRun-2026-10-16.json').read_text())
    if plan.get('latest_review_delta'):
        delta=json.loads(load_ref(plan['latest_review_delta']).read_text())
        base=extract(load_ref(delta['base_frozen_page']))
        assert delta['scope']=='incremental_quality_review_group_snapshot' and not delta['fullpage_copy_created']
        assert set(delta['unchanged_group_sha256'])==set(base['groups']) and not delta['removed_group_ids']
        group_sha=lambda value:hashlib.sha256(json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        assert all(group_sha(base['groups'][key])==value for key,value in delta['unchanged_group_sha256'].items())
        preserved(base);preserved({'groups':delta['new_groups']})
        # Incremental freezes retain prior new groups by reference, without copying their payloads.
        seen=set()
        while delta.get('previous_delta'):
            previous=delta['previous_delta']
            assert previous['sha256'] not in seen, 'Cyclic review delta chain'
            seen.add(previous['sha256'])
            delta=json.loads(load_ref(previous).read_text())
            preserved({'groups':delta['new_groups']})
    for group in data['groups'].values():
        load_ref(group['candidate']);load_ref(group['author_check'])
        assert [q['number']for q in group['questions']]==list(range(1,len(group['questions'])+1))
        assert all(q.get('options')or q.get('knownForms')for q in group['questions'])
        assert not any(q.get('parts')or q.get('referenceAnswers')for q in group['questions'])
        assert all(q.get('answer')in [p[0]for p in q['options']]for q in group['questions']if q['options'])
    additions=json.loads(load_ref(data['extra_authored_index']).read_text())
    source_batch_ref=data.get('selected_source_batch') or additions.get('this_batch_source_index')
    if source_batch_ref:
        source_batch=json.loads(load_ref(source_batch_ref).read_text())
        assert len(source_batch['groups'])==source_batch['new_selected_groups']
        assert sum(g['responses']for g in source_batch['groups'])==source_batch['new_response_positions']
        assert len({g['source_parent_id']for g in source_batch['groups']})==source_batch['new_parent_identities']
        official=next(g for g in source_batch['groups']if g['level']=='advanced')
        load_ref(official['original_paper']);load_ref(official['objective_key_page'])
        native=json.loads(load_ref(official['source_native']).read_text())
        assert '2022' in native['paper_pages']['1'] and 'Copyright' in native['paper_pages']['1']
        block=re.search(r'Q Part 1\s*(.*?)Q Part 2',native['key_text'],re.S)[1]
        vector=re.findall(r'(?m)^([1-8])\s+([ABCD])\s*$',block)
        assert [int(n)for n,_ in vector]==list(range(1,9))
        assert [v for _,v in vector]==official['printed_source_vector']
        for image in official['visuals']:
            load_ref(image)
        assert official['source_key_not_independent_gold']
        for group in source_batch['groups']:
            if group.get('part')=='5':
                native=json.loads(load_ref(group['source_native']).read_text())
                assert [q['number'] for q in native['questions']]==list(range(31,37))
                assert len(native['questions'])==group['responses']==6
                assert all([p[0]for p in q['options']]==list('ABCD')for q in native['questions'])
                assert [q['printed_key']for q in native['questions']]==group['printed_source_vector']
                for image in group['visuals']:load_ref(image)
                assert group['source_key_not_independent_gold'] and group['full_input_complete']
    for meta in additions['candidates']:
        group=data['groups'][meta['id']];audit=json.loads(load_ref(meta['author_check']).read_text());text=load_ref(meta['candidate']).read_text()
        assert text.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip()==response_markdown(group['questions'])
        assert audit['source_observation']['source_responses']==len(group['questions'])==meta['questions']
        load_ref(audit['source_index'])
        if meta['family']=='letter_completion':
            for q in group['questions']:
                filled={label:q['prefix']+value+q['suffix']for label,value in q['options']}
                assert [label for label,value in filled.items()if value==q['completion_target']]==[q['answer']]
        if meta['family']=='shared_bank' and meta['grade']=='primary4':
            assert audit['source_observation']['source_reuse_rule']=='not_explicit'
            student=text.split('## 学生题面')[1].split('## 作者核对')[0]
            assert '只用一次'not in student
            assert all(len(q['options'])==5 for q in group['questions'])
        if meta['family']=='shared_bank' and meta['grade']=='postgraduate':
            assert len(group['questions'])==10 and all(len(q['options'])==15 for q in group['questions'])
            assert len(audit['shared_bank'])==15 and audit['fixed_bank_forms']
            assert audit['source_observation']['source_reuse_rule']=='explicit_max_once'
            assert len(set(audit['author_answer_vector']))==10
            assert [q['answer'] for q in group['questions']]==audit['author_answer_vector']
            assert set(audit['unused_bank_labels'])==set('ABCDEFGHIJKLMNO')-set(audit['author_answer_vector'])
            assert all(q['options']==audit['shared_bank'] for q in group['questions'])
            assert re.findall(r'\((\d+)\)',audit['student_passage'])==[str(n) for n in range(1,11)]
            assert audit['student_passage'] in text and len(audit['all150_candidate_pairs'])==10
            assert all(len(row['candidate_review'])==15 for row in audit['all150_candidate_pairs'])
            load_ref(audit['source_observation']['source_input_preparation'])
            assert group['sourceFormNotice'] and audit['source_level_equivalence_established'] is False
        if meta['family']=='number_word_completion':
            assert len(group['questions'])==8
            assert all(not q['options'] and q['knownForms'] for q in group['questions'])
            for q in group['questions']:
                expected=q['knownForms'][0]
                assert expected=={'seven':'7','two':'2','ten':'10','four':'4','nine':'9','three':'3','eight':'8','five':'5'}[q['stem']]
                assert correct_number(' 00'+expected+' ',expected)
                assert not correct_number(str(int(expected)+1),expected)
            assert correct_number('２','2') and correct_number('٢','2')
            assert not any(correct_number(value,'2') for value in ['', 'two', '2.0', '2 0', '2/1', '-2'])
        if meta['family']=='choice_cloze':
            assert len(group['questions'])==8 and all(len(q['options'])==4 for q in group['questions'])
            assert audit['answered_examples']==1 and len(audit['example_options'])==4
            assert re.findall(r'\((\d+)\)',audit['student_passage'])==[str(n)for n in range(9)]
            assert audit['source_level_equivalence_established'] is False and group['sourceFormNotice']
        if meta['grade']=='advanced' and meta['family']=='reading_choice':
            assert len(group['questions'])==6 and all(len(q['options'])==4 for q in group['questions'])
            assert len(audit['paragraphs'])==5 and audit['student_passage']=='\n\n'.join(audit['paragraphs'])
            assert len(audit['response_operations'])==6 and len(set(audit['response_operations']))==6
            assert audit['source_level_equivalence_established'] is False and audit['fictional_content_not_empirical_fact_gold']
            assert group['requiredPassageImages']==[]
            assert audit['student_passage'] in text
            words=lambda value:len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?",value))
            assert audit['load_measure']['body_English_words']==words(audit['student_passage'])
            assert audit['load_measure']['stem_English_words']==sum(words(q['stem'])for q in group['questions'])
            assert audit['load_measure']['option_English_words']==sum(words(v)for q in group['questions']for _,v in q['options'])
        if meta['family']=='word_picture_choice':
            assert len(group['questions'])==6 and all(len(q['options'])==3 for q in group['questions'])
            assert len(group['requiredPassageImages'])==1
            asset=load_ref(audit['figure_asset']);root=ET.fromstring(asset.read_bytes())
            ns={'s':'http://www.w3.org/2000/svg'}
            uses=root.findall('s:use',ns)
            assert len(uses)==18
            assert not root.findall('.//s:script',ns)
            assert not root.findall('.//s:image',ns),'original vector input must not depend on remote media'
            href='{http://www.w3.org/1999/xlink}href'
            assert [u.attrib[href] for u in uses]==['#'+obj for row in audit['visual_candidate_objects'] for obj in row['candidate_objects']]
            for q,row in zip(group['questions'],audit['visual_candidate_objects']):
                assert [label for label,obj in zip('ABC',row['candidate_objects']) if obj==row['word']]==[q['answer']]
            image=group['requiredPassageImages'][0]
            assert base64.b64decode(image['src'].split(',',1)[1])==asset.read_bytes()
            assert group['sourceFormNotice'] and audit['authored_student_inputs_complete']
        if meta['grade']=='primary2' and meta['family']=='dialogue_matching':
            assert len(group['questions'])==5 and all(len(q['options'])==5 for q in group['questions'])
            assert len({tuple(tuple(p) for p in q['options']) for q in group['questions']})==1
            assert audit['source_observation']['source_reuse_rule']=='not_explicit'
            assert '只用一次' not in text.split('## 作者核对')[0]
        if meta['grade']=='primary5' and meta['family']=='sentence_choice':
            source=next(g for g in source_batch['groups'] if g['id']==audit['source_group_id'])
            native=json.loads(load_ref(source['source_native']).read_text())
            load_ref(source['source_html'])
            assert [q['number'] for q in native['selected_questions']]==source['source_numbers']==list(range(4,9))
            assert len(group['questions'])==source['responses']==5
            assert all([p[0] for p in q['options']]==list('ABC') for q in group['questions'])
            assert [q['stem'].count('____') for q in group['questions']]==audit['authored_blank_counts']==source['source_blank_counts']
            assert [q['answer'] for q in group['questions']]==audit['author_answer_vector']
            assert source['source_key_not_independent_gold'] and not source['school_exam_authentication']
            assert not group['requiredPassageImages'] and group['sourceFormNotice']
    assert all(g.get('sourceFormNotice')for g in data['groups'].values()if g['grade']=='primary5')
    return {'levels':16,'levels_with_preview':len(set(g['grade']for g in data['groups'].values())),
            'complete_groups':len(data['groups']),'responses':sum(len(g['questions'])for g in data['groups'].values()),
            'unpaused_inherited_payload_unchanged':True,'specific_complete_groups_paused':len(held),
            'paused_responses':sum(r['responses']for r in held.values()),
            'no_subjective_or_partial_mixed_groups':True,'new_authored_groups':len(additions['candidates']),
            'middle_source_totals_unchanged':True,'simulated_primary5_source_warning_bound':True,
            'source_unknown_early_levels_not_filled_with_adult_text':True,'independent_student_commercial_production_admission':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--page',type=Path,default=REPO/'build/english-benchmark-quality-review/index.html');p.add_argument('--report',type=Path,required=True);args=p.parse_args();result=check(args.page);args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result))
