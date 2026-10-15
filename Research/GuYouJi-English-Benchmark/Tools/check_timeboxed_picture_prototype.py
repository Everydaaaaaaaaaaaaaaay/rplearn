#!/usr/bin/env python3
"""Guard an authored picture prototype without upgrading missing source panels."""
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from grade_mode_evidence import BASE,evidence,load_ref
from quality_review_contract import response_markdown


def check(index,matrix):
    r=next(r for r in json.loads(index.read_text())['candidates']if r['id']=='grade10-future-plans-picture-prototype');a=json.loads(load_ref(r['author_check']).read_text());t=load_ref(r['candidate']).read_text();s=next(s for s in evidence()if s['id']==r['anchor_group_ids'][0]);q=a['review_response_tasks'][0]
    assert a['source_shape']==s['shape']and a['source_frozen_input_state']is False and s['necessary_input_complete']is False
    assert r['prototype_required_source_panels_missing']and a['prototype_required_source_panels_missing']and a['source_panel_count']=='unknown'and a['source_role_assignments']=='unknown'
    assert a['author_designed_panel_count']==3 and a['author_designed_given_panels']==2 and a['authored_student_inputs_complete']
    assert a['questions']==1 and len(a['review_response_tasks'])==1 and len(q['parts'])==1 and q['parts'][0]['opening']
    block=t.split('<!-- responses:start -->')[1].split('<!-- responses:end -->')[0].strip();assert block==response_markdown([q])and hashlib.sha256(block.encode()).hexdigest()==a['canonical_response_block_sha256']
    assert a['candidate_sha256']==r['candidate']['sha256']and a['word_target']==70 and a['target_relation']=='about'and a['given_opening_excluded_from_word_target']
    assert a['reference_new_body_words']==len(a['reference_new_body'].split())and a['reference_given_opening_words']==len(q['parts'][0]['opening'].split())
    assert q['referenceAnswers']==[q['parts'][0]['opening']+' '+a['reference_new_body']]
    raw=load_ref(a['figure_asset']).read_bytes();root=ET.fromstring(raw);assert root.attrib['viewBox']=='0 0 1110 390'and root.attrib['width']=='1110'and root.attrib['height']=='390'
    assert all(x in raw.decode()for x in ['At home','College open day','Later at home','Mum','Tutor','training?'])
    cell=next(c for c in json.loads(matrix.read_text())['cells']if c['grade']==10 and c['family']=='picture_continuation');assert cell['delivery_state']=='author_prototype_source_mode_pending'and cell['selected_representative_id']==r['id']
    assert all(a[k]is False for k in ['independent_review','student_calibration','commercial_admission','production_admission','model_or_production_evaluation_called'])
    return {'author_student_input_complete':True,'source_required_panels_still_missing':True,'source_mode_verified':False,'prototype_status_not_complete_source_pattern':True,'source_frame_count_not_inferred_from_answer':True,'figure_SHA_and_size_verified':True,'whole_task_responses':1,'new_body_reference_words':a['reference_new_body_words'],'given_opening_reference_words':a['reference_given_opening_words'],'source_count_increment':0,'independent_student_commercial_or_production':False}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--index',type=Path,required=True);p.add_argument('--matrix',type=Path,required=True);p.add_argument('--report',type=Path,required=True);args=p.parse_args();r=check(args.index,args.matrix);args.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
