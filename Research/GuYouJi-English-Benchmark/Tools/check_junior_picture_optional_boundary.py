"""Validate two separate closed BNU G8 reading sections against frozen original inputs."""
import hashlib,json,re
from grade_mode_evidence import load_ref

def sha(t):return hashlib.sha256(t.encode()).hexdigest()
def validate(r,prior):
 assert r['level']==8 and r['source_count_increment']==r['new_author_groups']==0 and not r['source_key_is_gold']
 assert r['source_full_inputs_verified'] and r['original_unknown_observations_retained'] and not r['grade_exclusivity_established']
 load_ref(r['source_PDF']);native=json.loads(load_ref(r['native_pages']).read_text());assert native['source_sha256']==r['source_PDF']['sha256']
 projection=json.loads(load_ref(r['source_projection']).read_text());assert projection['source_PDF']==r['source_PDF'] and projection['source_key_not_gold']
 for span in projection['native_spans']:
  assert span['native_pages']==r['native_pages'];raw=next(p['text']for p in native['pages']if p['PDF_page']==span['PDF_page']);selected=raw[span['start_offset']:span['end_offset']];assert sha(selected)==span['sha256'] and selected.strip()
 for key in ['source_pages','source_key_pages']:
  assert r[key]
  for a in r[key]:load_ref(a)
 private=json.loads(load_ref(r['existing_private_review']).read_text());assert private['source_paper_acquisition_id']==r['paper_id']
 originals={m['id']:m for m in prior['unreviewed_records']};assert r['source_observations'] and all(originals[m['id']]==m for m in r['source_observations'])
 assert all(m['necessary_input_complete']is None and m['positive_answer_anchor_admitted']is False and m['production_supported']is False for m in r['source_observations'])
 cfg=r['configuration'];assert cfg['all_selected_subgroups_mandatory'] and not cfg['necessary_audio']
 assert cfg['responses']==r['responses']==sum(cfg['response_distribution']) and [g['responses']for g in r['subgroups']]==cfg['response_distribution']
 assert sum(cfg['material_unit_distribution'])==cfg['text_unit_count'] and cfg['points_each']==2 and cfg['selected_objective_points']==2*r['responses']
 assert len(r['published_keys'])==r['responses'] and all(len(q['published_answer'])==1 and q['published_answer']in'ABCD'for q in r['published_keys'])
 keys={q['number']:q['published_reference']for g in private['groups']for q in g['private_responses']if g['kind']in['imageMatching','readingB','readingC','optionalReading']}
 for q in r['published_keys']:assert keys[q['number']]==q['published_answer']==projection['published_keys'][str(q['number'])]
 identity=r['source_identity'];assert identity['declared_question_pages']==12 and identity['public_repost_actual_question_pages']==10 and identity['conflict_preserved'] and identity['source_optional_not_higher_product_level_or_CEFR']
 if r['kind']=='mixed_closed_reading':
  assert [load_ref(a).name for a in r['source_pages']]==['grade8-bnu2026-inspection-'+str(n).zfill(2)+'.png'for n in[4,5,6,7]]
  assert [load_ref(a).name for a in r['source_key_pages']]==['grade8-bnu2026-inspection-'+str(n).zfill(2)+'.png'for n in[12,13]]
  assert r['options_each']==4 and r['responses']==11 and cfg['response_distribution']==[3,4,4]
  assert cfg['options_each_by_subgroup']==[4,4,4] and cfg['candidate_rule_by_subgroup']==['one_shared_four_device_picture_bank','independent_four_per_question','independent_four_per_question']
  assert cfg['material_unit_distribution']==[3,1,1] and cfg['selected_objective_points']==22 and cfg['umbrella_reading_points32_not_selected22'] and cfg['separate_open44to47_10points_paused']
  assert cfg['A_extra_candidates']==1 and cfg['A_each_entry_once_explicit']is False and cfg['A_observed_key_distinct']
  assert r['additional_existing_sibling_member']=='g8.bnu2026.imageMatching' and any(g['id']==r['additional_existing_sibling_member']for g in private['groups'])
  assert [q['number']for q in r['published_keys']]==list(range(33,44))
  assert len(projection['A_profiles'])==3 and [p['number']for p in projection['A_profiles']]==[33,34,35]
  assert [p['published_answer']for p in projection['A_profiles']]==list('BDA') and all(p['name']and p['text']for p in projection['A_profiles'])
  assert [p['label']for p in projection['A_picture_panels']]==list('ABCD') and all(p['visible']for p in projection['A_picture_panels'])
  assert projection['B_paragraph_count']==6 and projection['B_page6_first_lines_continue_last_paragraph_not_new_paragraph']
  assert projection['C_paragraph_count']==6 and projection['C_target_phrase']=='integrated with' and projection['C_target_paragraph']==3
  assert projection['C_question_names_underlined_but_line_not_visible_in_original_raster_and_crop'];load_ref(r['target_phrase_crop'])
  assert [int(n)for n in re.findall(r'(?m)^(\d{2})\.',projection['B_questions']+'\n'+projection['C_questions'])]==list(range(36,44))
  assert 'I didn\'t debate that season.'in projection['B_body_fragments'][0] and 'But I had no regrets'in projection['B_body_fragments'][1]
  assert 'over 70%'in' '.join(projection['C_body_fragments']) and 'one in three'in' '.join(projection['C_body_fragments'])
 else:
  assert [load_ref(a).name for a in r['source_pages']]==['grade8-bnu2026-inspection-'+str(n).zfill(2)+'.png'for n in[9,10]]
  assert [load_ref(a).name for a in r['source_key_pages']]==['grade8-bnu2026-inspection-15.png']
  assert r['kind']=='reading_choice' and r['responses']==3 and r['options_each']==4
  assert cfg['response_distribution']==[3] and cfg['optional_umbrella10_not_selected6'] and cfg['separate_grammar53to56_4points_excluded']
  assert cfg['report_paragraphs']==6 and cfg['example_paragraph']==3 and not cfg['required_images'] and not cfg['shared_candidates']
  assert [q['number']for q in r['published_keys']]==[57,58,59] and [q['published_answer']for q in r['published_keys']]==list('DDC')
  assert projection['optional_paragraph_count']==6 and projection['optional_example_paragraph']==3 and projection['optional57B_support_risk_not_silent_multikey_or_keyfix']
  assert 'naturally'in projection['optional_body'] and 'learn,grow'in projection['optional_body'] and 'at least an hour'in projection['optional_body']
  raw='\n'.join(projection['optional_questions_fragments']);assert [int(n)for n in re.findall(r'(?m)^(\d{2})\.',raw)]==[57,58,59]
 assert r['source_quality_risks'] and r['same_specific_whole_section_authors']==0
 return True
