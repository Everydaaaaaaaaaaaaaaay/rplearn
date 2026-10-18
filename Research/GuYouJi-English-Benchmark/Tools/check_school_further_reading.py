#!/usr/bin/env python3
"""Verify three public-description section boundaries, not original-paper gold."""
import argparse,copy,hashlib,json,re
from pathlib import Path
from bs4 import BeautifulSoup
from grade_mode_evidence import load_ref

def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def selected(p):
 raw=load_ref(p['source']).read_text();text=raw[p['start_offset']:p['end_offset']];assert digest(text)==p['sha256']
 if 'text'in p:assert p['text']==text
 return text

def validate(r,prior):
 assert r['kind']=='reading_choice' and r['source_count_increment']==r['new_author_groups']==0
 assert r['source_full_inputs_verified'] and not r['source_key_is_gold'] and not r['grade_exclusivity_established']
 assert r['full_input_verification_scope']=='selected public-description textual inputs and all candidates;not original-paper facsimile or absence of decorative photos'
 assert r['original_unknown_observations_retained'] and r['full_body_and_all_candidates_context_read']
 assert r['requires_source_binding_and_specific_author_contract'] and not r['authors_genre_model_ready']
 existing=[x for x in prior['unreviewed_records']if x['paper_id']==r['paper_id']];assert r['source_observations']==existing
 assert all(x['necessary_input_complete']in [None,True] for x in existing)
 raw=load_ref(r['source_text']).read_text();soup=BeautifulSoup(load_ref(r['source_parent_html']).read_text(),'html.parser');intro=soup.select('p.assets-intro');assert len(intro)==1 and len(intro[0].find_all('img'))==r['public_description_has_inline_images']==0
 assert r['source_html_title']==soup.title.get_text() and r['body_cover_first_lines']==raw.splitlines()[:8]
 c=r['configuration'];assert c['responses']==r['responses'] and c['options_each']==r['options_each']
 assert c['passage_count']==c['subgroup_count']==len(r['subgroups'])==len(existing)
 assert c['response_distribution']==[g['responses']for g in r['subgroups']]
 assert c['material_unit_distribution']==[g['material_units']for g in r['subgroups']]
 assert sum(c['response_distribution'])==r['responses'] and sum(c['material_unit_distribution'])==c['text_unit_count']
 assert c['responses']*c['points_each']==c['selected_objective_points']
 assert c['all_selected_subgroups_mandatory'] and not c['shared_candidates'] and not c['necessary_audio']
 assert not c['required_images'] and not c['required_tables'] and c['original_decorative_media_absence_not_established']
 header=selected(r['selected_objective_header']);selected(r['whole_objective_header']);selected(r['source_section'])
 assert int(re.search(r'共\s*(\d+)\s*小题',header)[1])==r['responses']
 assert float(re.search(r'每小题\s*([\d.]+)\s*分',header)[1])==c['points_each']
 assert float(re.search(r'(?:满分|计)\s*([\d.]+)\s*分',header)[1])==c['selected_objective_points']
 allnumbers=[]
 for g,ob in zip(r['subgroups'],existing):
  assert g['source_member_id']==ob['id'] and ob['shape']['responses']==g['responses'] and ob['shape']['options_each']==g['options_each']==r['options_each']
  body=selected(g['body']);qt=selected(g['question_block']);assert body.strip() and '【答案】'not in body+qt
  matches=list(re.finditer(r'(?m)^(\d+)\.(.*?)(?=^\d+\.|\Z)',qt,re.S));assert [int(m[1])for m in matches]==g['question_numbers']
  assert len(g['questions'])==g['responses'];allnumbers+=g['question_numbers']
  for q,m in zip(g['questions'],matches):
   assert q['number']==int(m[1]) and selected(q['whole_question'])==m[0]
   text=m[2];marks=[(a[1],a.start(),a.end())for a in re.finditer(r'(?:^|\s)([A-D])\.',text)]
   for anomaly in r['punctuation_anomalies']:
    if anomaly['number']!=q['number']:continue
    assert anomaly['normal_period_missing_preserved'];needle=anomaly['literal_marker'];pos=text.index(needle);marks.append((anomaly['label'],pos,pos+len(needle)))
   marks.sort(key=lambda x:x[1]);assert [a[0]for a in marks]==list('ABCD')[:r['options_each']]
   assert [a['label']for a in q['options']]==list('ABCD')[:r['options_each']]
   for i,(label,start,end)in enumerate(marks):assert digest(text[end:marks[i+1][1]if i+1<len(marks)else len(text)].strip())==q['options'][i]['text_sha256']
 assert allnumbers==list(range(allnumbers[0],allnumbers[0]+r['responses']))
 if r['level']in [7,12]:
  assert [g['label']for g in r['subgroups']]==list('ABCD') and c['response_distribution']==[3,4,4,4]
  selected(r['A_intro']);units=[selected(x)for x in r['A_profiles']];assert len(units)==c['material_unit_distribution'][0]
  assert selected(r['A_intro'])+''.join(units)==selected(r['subgroups'][0]['body'])
  kt=selected(r['key_block'])
 else:
  assert r['level']==9 and c['response_distribution']==[5,5] and c['material_unit_distribution']==[4,1]
  assert c['points_each']==2 and c['selected_objective_points']==20 and r['outer_reading_points30_selected_MC20_notTF10']
  units=[selected(x)for x in r['email_units']];assert len(units)==4 and all(all(k in x for k in ['From:','To:','Sent:','Subject:'])for x in units)
  assert ''.join(units)==selected(r['subgroups'][0]['body'])
  assert len(r['separate_TF5_already_authored'])==3
  for a in r['separate_TF5_already_authored']:load_ref(a['candidate']);load_ref(a['author_check'])
  kt='\n'.join(selected(g['key_block'])for g in r['subgroups'])
 keys=[dict(number=int(n),published_answer=a)for n,a in re.findall(r'(\d+)\.\s*([A-D])',kt)];assert keys==r['published_keys'] and [x['number']for x in keys]==allnumbers
 if r['level']==7:
  assert c['required_lists']==['B.six_time_stamped_diary_entries']
  B=selected(r['subgroups'][1]['body']);assert r['diary_timestamps']==['5 a. m.','7 a. m.','8 a. m.','3 p. m.','9 p. m.','12 a. m.'] and all(t in B for t in r['diary_timestamps'])
  assert r['D_inline_missing_turn_marker']=='▲' and '▲'in selected(r['subgroups'][3]['body'])
 if r['level']==12:assert c['whole_reading_points50_not_selected37_5'] and c['selected_objective_points']==37.5
 return True

def run(path):
 doc=json.loads(path.read_text());prior=json.loads(load_ref(doc['previous_reconciliation']).read_text());rows=[]
 for r in doc['records']:
  validate(r,prior);cases={'whole_count_as_single':lambda x:x.__setitem__('responses',x['subgroups'][0]['responses']),'one_subgroup_lost':lambda x:x['subgroups'].pop(),'options_lost':lambda x:x['subgroups'][0]['questions'][0]['options'].pop(),'body_SHA_wrong':lambda x:x['subgroups'][0]['body'].__setitem__('sha256','0'*64),'header_SHA_wrong':lambda x:x['selected_objective_header'].__setitem__('sha256','0'*64),'old_input_flag_overwritten':lambda x:x['source_observations'][0].__setitem__('necessary_input_complete',True if x['source_observations'][0]['necessary_input_complete'] is None else None),'key_silently_repaired':lambda x:x['published_keys'][0].__setitem__('published_answer','B'if x['published_keys'][0]['published_answer']=='A'else'A'),'gold_upgrade':lambda x:x.__setitem__('source_key_is_gold',True),'profile_count_collapsed':lambda x:x['configuration']['material_unit_distribution'].__setitem__(0,1),'original_photos_absence_claim':lambda x:x['configuration'].__setitem__('original_decorative_media_absence_not_established',False),'truncated_six':lambda x:x['subgroups'][0]['questions'].__delitem__(slice(1,None))}
  if r['level']==9:cases.update({'email_header_lost':lambda x:x['email_units'].pop(),'outer30_as20':lambda x:x['configuration'].__setitem__('selected_objective_points',30),'TF_authors_missing':lambda x:x['separate_TF5_already_authored'].pop()})
  elif r['level']==7:cases.update({'diary_time_lost':lambda x:x['diary_timestamps'].pop(),'inline_turn_lost':lambda x:x.__setitem__('D_inline_missing_turn_marker',''),'third_home_profile_lost':lambda x:x['A_profiles'].pop()})
  else:cases.update({'fourth_cave_lost':lambda x:x['A_profiles'].pop(),'whole50_as37_5':lambda x:x['configuration'].__setitem__('selected_objective_points',50)})
  rejected=[]
  for name,fn in cases.items():
   bad=copy.deepcopy(r);fn(bad)
   try:validate(bad,prior)
   except(AssertionError,IndexError,KeyError,ValueError):rejected.append(name)
   else:raise AssertionError('Accepted '+name)
  rows.append(dict(id=r['id'],responses=r['responses'],candidate_positions=r['responses']*r['options_each'],negative_controls=rejected))
 return dict(records=rows,source_sections=3,responses=40,candidate_positions=150,negative_controls=sum(len(r['negative_controls'])for r in rows),new_authors=0,new_source_downloads=0,source_key_and_original_facsimile_not_gold=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.review);assert not a.report.exists();a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
