"""Bind the original Fengtai-label G8 complete reading13, including its media."""
import json,re
from grade_mode_evidence import load_ref

def validate(r,prior):
 assert r['level']==8 and r['kind']=='mixed_closed_reading' and r['responses']==13 and r['options_each']==4
 assert r['source_count_increment']==r['new_author_groups']==0 and r['same_specific_whole_section_authors']==0
 assert r['source_full_inputs_verified'] and not r['source_key_is_gold'] and r['original_unknown_observations_retained'] and not r['grade_exclusivity_established']
 original={m['id']:m for m in prior['unreviewed_records']};assert len(r['source_observations'])==3
 assert all(original[m['id']]==m and m['necessary_input_complete']is None and not m['positive_answer_anchor_admitted']for m in r['source_observations'])
 assert {m['id']for m in r['source_observations']}=={'g8.fengtai2026.readingB','g8.fengtai2026.readingC','g8.fengtai2026.readingD'}
 p=json.loads(load_ref(r['source_projection']).read_text());load_ref(r['source_PDF']);native=json.loads(load_ref(r['native_pages']).read_text())
 assert p['source_PDF']==r['source_PDF'] and native['source_sha256']==r['source_PDF']['sha256']
 assert all(not n['text']for n in native['pages']if n['PDF_page']<=10) and p['native_firstten_empty_not_used_as_text_evidence']
 assert [load_ref(a).name for a in r['source_pages']]==[f'grade8-fengtai2026-inspection-{n:02}.png'for n in[2,3,4,5,6]]
 assert [load_ref(a).name for a in r['source_key_pages']]==['grade8-fengtai2026-inspection-09.png']
 assert r['source_pages']==p['source_pages'] and r['source_key_pages']==p['source_key_pages'];load_ref(p['identity_page'])
 cfg=r['configuration'];assert cfg['response_distribution']==[3,3,4,3] and cfg['material_unit_distribution']==[3,1,1,1] and cfg['text_unit_count']==6
 assert cfg['passage_count']==cfg['subgroup_count']==4 and cfg['responses']==13 and cfg['options_each_by_subgroup']==[4]*4
 assert cfg['candidate_rule_by_subgroup']==['one_shared_four_activity_scene_picture_bank','independent_four_per_question','independent_four_per_question','independent_four_per_question']
 assert cfg['points_each']==2 and cfg['selected_objective_points']==26 and cfg['all_selected_subgroups_mandatory'] and not cfg['necessary_audio']
 assert cfg['A_extra_candidates']==1 and cfg['A_each_entry_once_explicit']is False and cfg['A_observed_key_distinct']
 assert cfg['B_paragraphs']==9 and cfg['C_paragraphs']==6 and cfg['D_paragraphs']==5 and cfg['inline_gloss_distribution_BCD']==[2,4,7]
 assert cfg['required_images']==['A.four_activity_scene_candidates_in_2by2_grid','A.three_profile_faces','B.mower_wordhelp_figure_with_lawn_mower_caption']
 assert [g['responses']for g in r['subgroups']]==[3,3,4,3] and [g['question_numbers']for g in r['subgroups']]==[list(range(21,24)),list(range(24,27)),list(range(27,31)),list(range(31,34))]
 assert len(p['A_profiles'])==3 and [x['number']for x in p['A_profiles']]==[21,22,23] and p['A_three_profile_faces_present']
 assert [x['label']for x in p['A_picture_panels']]==list('ABCD') and all(x['visible']for x in p['A_picture_panels'])
 assert p['B_wordhelp_figure']['caption']=='lawn mower' and p['B_wordhelp_figure']['visible']
 assert [len(p[k+'_paragraphs'])for k in'BCD']==[9,6,5] and p['B_paragraph2_continues_frompage3_to4']
 assert p['C_tip_headings']==[None,'Explore the Unknown','Take Mistakes as Chances','Help Them Find Interesting Outlets'] and p['C_first_heading_blank_for_Q27_not_sentence_insertion']
 assert p['D_underlined_phrase']=='adhering to' and p['D_underlined_paragraph']==2 and p['D_underlined_phrase']in p['D_paragraphs'][1]
 assert p['D_confirmed_phrase']=='while consent is a careful yes based on our values.' and p['D_confirmed_phrase']in p['D_paragraphs'][1]
 assert p['preliminary_carefully_misread_is_transcription_error_not_source_typo'];load_ref(p['D_confirming_phrase_crop'])
 for part,count in[('B',2),('C',4),('D',7)]:
  pairs=p[part+'_inline_glosses'];assert len(pairs)==count;text=' '.join(p[part+'_paragraphs'])
  assert all(text.count(en+' ('+zh+')')==1 for en,zh in pairs)
 assert [q['number']for q in p['questions']]==list(range(24,34))
 for q in p['questions']:
  assert [k for k,t in q['options']]==list('ABCD') and all(t.strip()for k,t in q['options']) and q['published_answer']==p['published_keys'][str(q['number'])]
 assert 'heading for Paragraph 2'in p['questions'][3]['stem'] and 'Einstein in Paragraph 3'in p['questions'][4]['stem']
 assert p['source_key_not_gold'] and p['source28A_and32C_related_support_risks_retained']
 assert r['published_keys']==[dict(number=n,published_answer=p['published_keys'][str(n)])for n in range(21,34)]
 private=json.loads(load_ref(r['existing_private_review']).read_text());assert private['source_paper_acquisition_id']==r['paper_id']
 keys={q['number']:q['published_reference']for g in private['groups']if g['kind']in['imageMatching','readingB','readingC','readingD']for q in g['private_responses']}
 assert keys=={q['number']:q['published_answer']for q in r['published_keys']} and r['additional_existing_sibling_member']=='g8.fengtai2026.imageMatching'
 assert r['source_identity']['title']=='2026 北京丰台初二（上）期末 英语' and r['source_identity']['date']=='2026.01' and r['source_identity']['region_label_not_originalschool_authentication']
 assert r['source_quality_risks'] and r['old_matching3_not_whole13'] and r['requires_source_binding_and_specific_author_contract']
 return True
