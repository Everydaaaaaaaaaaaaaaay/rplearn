"""Check source-bound visual/mixed reading boundaries without converting keys to gold."""
import argparse,copy,hashlib,json,re,calendar
from pathlib import Path
from grade_mode_evidence import load_ref

def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def selected(p):
 t=load_ref(p['source']).read_text()[p['start_offset']:p['end_offset']];assert digest(t)==p['sha256'];return t

def validate(r,prior):
 assert r['level']==7 and r['new_author_groups']==r['source_count_increment']==0
 assert r['source_full_inputs_verified'] and not r['source_key_is_gold'] and not r['authors_genre_model_ready']
 assert r['original_unknown_observations_retained'] and r['requires_source_binding_and_specific_author_contract'] and not r['grade_exclusivity_established']
 expected=[x for x in prior['unreviewed_records']if x['id']in{y['id']for y in r['source_observations']}];assert r['source_observations']==expected and expected
 c=r['configuration'];assert c['responses']==r['responses']==sum(c['response_distribution'])
 assert len(r['subgroups'])==c['subgroup_count']==c['passage_count']
 assert [s['responses']for s in r['subgroups']]==c['response_distribution']
 assert [s['material_units']for s in r['subgroups']]==c['material_unit_distribution'] and sum(c['material_unit_distribution'])==c['text_unit_count']
 assert c['responses']*c['points_each']==c['selected_objective_points'] and c['all_selected_subgroups_mandatory'] and not c['necessary_audio']
 assert [q['number']for q in r['published_keys']]==[n for g in r['subgroups']for n in g['question_numbers']]
 if r.get('source_text'):
  assert r['kind']=='reading_choice' and r['options_each']==4 and r['responses']==15
  assert c['response_distribution']==[3,3,4,5] and c['material_unit_distribution']==[1,1,1,3] and c['selected_objective_points']==30
  whole=selected(r['source_section']);assert '共15小题' in whole and '每小题2分'in whole and '满分30分'in whole
  for g in r['subgroups']:
   body=selected(g['body']);qt=selected(g['question_block']);assert body.strip()
   ns=[int(m[1])for m in re.finditer(r'(?m)^\s*(\d+)\s*\.',qt)];assert ns==g['question_numbers']
  for k in ['source_parent_html','source_calendar','source_picture_candidates','published_key_image']:load_ref(r[k])
  assert c['required_images']==['A.June2019calendar','B.Q51four_picture_candidates'] and c['required_tables']==['A.month_calendar']
  assert c['required_lists']==['D.three_numbered_poems','D.four_entry_word_glossary'] and r['D_poems']==3 and len(r['D_glossary'])==4
  assert r['source_image_panel_order']==[['A','B'],['C','D']]
  cal=r['calendar_observation'];assert cal['year']==2019 and cal['month']=='June' and cal['weekday_headers_low_resolution_not_transcribed']
  assert cal['first_date_column1based']==calendar.weekday(2019,6,1)+2==7
  assert [d for d in range(1,31)if calendar.weekday(2019,6,d)==6][2]==cal['thirdSunday_day']==16
  assert ''.join(q['published_answer']for q in r['published_keys'])=='CBCBDABDBDDDCAD'
  assert len(r['existing_partial_authors'])==3 and r['same_specific_whole_section_authors']==0
 else:
  x=json.loads(load_ref(r['source_projection']).read_text());assert r['source_PDF']==x['source_PDF'];load_ref(r['source_PDF'])
  assert all(p in x['source_pages']for p in r['source_pages']+r['source_key_pages'])
  for p in r['source_pages']+r['source_key_pages']:load_ref(p)
  fields=[k for g in r['subgroups']for k in g['projection_keys']];assert set(fields)==set(r['projection_field_sha256'])
  for k in fields:assert digest(json.dumps(x[k],sort_keys=True,ensure_ascii=False))==r['projection_field_sha256'][k]
  if r['kind']=='mixed_closed_reading':
   assert r['options_each']is None and r['responses']==11 and c['selected_objective_points']==22 and c['umbrella_reading_points30_not_selected22']
   assert c['response_distribution']==[3,4,4] and c['material_unit_distribution']==[7,1,1]
   assert c['options_each_by_subgroup']==[4,3,3] and c['shared_candidates_only_A']
   assert c['candidate_rule_by_subgroup']==['one_shared_four_activity_bank','independent_three_per_question','independent_three_per_question']
   assert len(x['cards'])==c['A_activity_cards']==4 and len(x['profiles'])==c['A_profiles']==3 and c['A_extra_candidates']==1
   assert not c['A_each_entry_once_explicit'] and not x['A_reuse_rule_explicit'] and c['A_observed_key_distinct']
   assert len(set(p['published_answer']for p in x['profiles']))==3 and all(all(card[k]for k in ['label','title','text','time','place','pictogram'])for card in x['cards'])
   assert c['required_images']==['A.four_activity_pictograms_and_three_profile_faces','B.apple_picking_illustration','B.pot_stove_illustrated_gloss']
   assert c['required_tables']==['A.two_by_two_activity_cards'] and c['required_lists']==['C.two_printed_subheadings_and_42placeholder']
   assert x['B_illustrated_glosses']==['pot','stove'] and x['B_narrative_illustration']
   assert r['source_C_paragraphs']==1+sum(len(z['paragraphs'])for z in x['C_sections'])==5
   assert x['C_sections'][-1]['heading']=='____42____' and r['source_C_heading_blank42']
   assert x['C_underlined_phrase']==r['source_C_underlined_phrase']=='strengthen the bond with'
   assert r['source_C_friendship_grow_preserved'] and 'friendship grow'in x['C_sections'][1]['paragraphs'][1]
   qs=x['profiles']+x['B_questions']+x['C_questions'];assert ''.join(q['published_answer']for q in qs)=='CADACCBCAAB'
   assert [dict(number=q['number'],published_answer=q['published_answer'])for q in qs]==r['published_keys']
   assert x['open_section44to47_paused_not_included'] and len(r['existing_partial_matching_authors'])==3 and r['existing_matching3not_whole11']
  else:
   assert r['kind']=='reading_choice' and r['responses']==r['options_each']==3 and c['selected_objective_points']==6
   assert c['optional_umbrella10_not_selected6'] and c['separate_grammar56to59_not_included'] and x['optional_separate_grammar56to59_4points_not_included']
   assert len(x['optional_paragraphs'])==c['report_paragraphs']==6 and c['source_sample_size']==3595 and c['source_recall_window_months']==3
   assert x['not_medical_advice_or_diagnosis'] and x['optional62_parent_to_friend_generalization_not_silent_repair']
   assert [dict(number=q['number'],published_answer=q['published_answer'])for q in x['optional_questions']]==r['published_keys']
   assert [q['published_answer']for q in r['published_keys']]==list('BBA')
 return True

def run(path):
 doc=json.loads(path.read_text());prior=json.loads(load_ref(doc['previous_reconciliation']).read_text());all_ids=[o['id']for r in doc['records']for o in r['source_observations']];assert len(all_ids)==len(set(all_ids))==doc['new_classified_old_reading_records']==5
 result=[]
 for r in doc['records']:
  validate(r,prior);cases={'fixedsix':lambda x:x.__setitem__('responses',6),'one_subgroup_lost':lambda x:x['subgroups'].pop(),'sourceflag_overwrite':lambda x:x['source_observations'][0].__setitem__('necessary_input_complete',True),'gold_upgrade':lambda x:x.__setitem__('source_key_is_gold',True),'wrong_total':lambda x:x['configuration'].__setitem__('selected_objective_points',50),'membercounts_as_units':lambda x:x['configuration'].__setitem__('text_unit_count',2 if x['configuration']['text_unit_count']==1 else 1)}
  if r.get('source_text'):
   cases.update({'calendar_asset_lost':lambda x:x.pop('source_calendar'),'picture_asset_lost':lambda x:x.pop('source_picture_candidates'),'one_poem_lost':lambda x:x.__setitem__('D_poems',2),'gloss_lost':lambda x:x['D_glossary'].pop(),'calendar_header_guessed':lambda x:x['calendar_observation'].__setitem__('weekday_headers_low_resolution_not_transcribed',False),'wrong_date':lambda x:x['calendar_observation'].__setitem__('thirdSunday_day',23),'wrong_key':lambda x:x['published_keys'][0].__setitem__('published_answer','A')})
  elif r['kind']=='mixed_closed_reading':
   cases.update({'pure_ABC_recast':lambda x:x.__setitem__('options_each',3),'matching3_as_whole11':lambda x:x.__setitem__('existing_matching3not_whole11',False),'shared_bank_for_all':lambda x:x['configuration'].__setitem__('candidate_rule_by_subgroup',['one_shared_four_activity_bank']*3),'reuse_ban_invented':lambda x:x['configuration'].__setitem__('A_each_entry_once_explicit',True),'one_card_lost':lambda x:x['configuration'].__setitem__('A_activity_cards',3),'one_gloss_lost':lambda x:x['configuration']['required_images'].pop(),'underlined_phrase_drift':lambda x:x.__setitem__('source_C_underlined_phrase','stronger than'),'heading_blank_lost':lambda x:x.__setitem__('source_C_heading_blank42',False),'whole30_as22':lambda x:x['configuration'].__setitem__('selected_objective_points',30),'projection_SHA_drift':lambda x:x['projection_field_sha256'].__setitem__('B_paragraphs','0'*64)})
  else:cases.update({'optional10_as6':lambda x:x['configuration'].__setitem__('selected_objective_points',10),'grammar_merged':lambda x:x['configuration'].__setitem__('separate_grammar56to59_not_included',False),'recall_window_lost':lambda x:x['configuration'].__setitem__('source_recall_window_months',1),'whole_sample_changed':lambda x:x['configuration'].__setitem__('source_sample_size',3959),'sixparagraphs_lost':lambda x:x['configuration'].__setitem__('report_paragraphs',5),'projection_SHA_drift':lambda x:x['projection_field_sha256'].__setitem__('optional_questions','0'*64)})
  rejected=[]
  for name,fn in cases.items():
   bad=copy.deepcopy(r);fn(bad)
   try:validate(bad,prior)
   except(AssertionError,IndexError,KeyError,ValueError):rejected.append(name)
   else:raise AssertionError('Accepted '+name)
  result.append(dict(id=r['id'],responses=r['responses'],negative_controls=rejected))
 return dict(records=result,negative_controls=sum(len(r['negative_controls'])for r in result),old_reading_records_classified=5,new_authors=0,new_downloads=0,new_rendered_pages=0,keys_and_semantics_not_independent_gold=True)
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--review',type=Path,required=True);p.add_argument('--report',type=Path,required=True);a=p.parse_args();r=run(a.review);assert not a.report.exists();a.report.write_text(json.dumps(r,ensure_ascii=False,indent=2)+'\n');print(json.dumps(r))
