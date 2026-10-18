"""Source-bound G12 cave profiles, friendship, river history and future forecasts."""
import json
from grade_mode_evidence import load_ref
from check_school_further_reading import validate as validate_boundary
from email_reading_contract import digest
from senior_reading_contract import render,body_text

OPERATIONS=['cave_distinctive_feature','cave_season_detail','cross_cave_common_feature','friendship_origin','figurative_support_quote','distance_relationship_inference','profile_purpose','river_city_role','parallel_street_numbering','twentieth_century_infrastructure','river_reconnection_ideal','future_car_capability','paragraph_four_mechanism','context_imperative_meaning','final_paragraph_prediction_purpose']

def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());validate_boundary(s,json.loads(load_ref(review['previous_reconciliation']).read_text()))
 assert b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert b['task_mode']=='school_senior_caves_friendship_river_forecast15' and b['author_gate']=='grade12_caves_friendship_river_forecast15_v1'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 assert d['grade']==b['level']==s['level']==12 and d['family']==b['family']==s['kind']=='reading_choice'
 c=s['configuration'];assert s['responses']==b['responses']==15 and s['options_each']==b['options_each']==4
 assert c['response_distribution']==[3,4,4,4] and c['material_unit_distribution']==[4,1,1,1]
 assert c['points_each']==2.5 and c['selected_objective_points']==37.5 and c['whole_reading_points50_not_selected37_5']
 sections=d['sections'];qs=d['questions'];assert [x['label']for x in sections]==list('ABCD')
 assert [x['response_numbers']for x in sections]==[list(range(1,4)),list(range(4,8)),list(range(8,12)),list(range(12,16))]
 for sec,src in zip(sections,s['subgroups']):
  assert sec['genre']==src['genre'] and len(sec['units'])==src['material_units'] and all(u.strip()for u in sec['units'])
 assert sections[0]['intro'].strip() and all(not x.get('intro')for x in sections[1:])
 assert len(d['cave_titles'])==len(set(d['cave_titles']))==4 and all(u.startswith(name+'\n')for u,name in zip(sections[0]['units'],d['cave_titles']))
 friend=d['friendship'];B=sections[1]['units'][0];assert friend['origin']in B and friend['figurative_quote']in B and friend['distance_effort_and_value']in B and friend['legacy']in B
 river=d['river'];C=sections[2]['units'][0];assert river['flow_direction']in['west_to_east','east_to_west','north_to_south','south_to_north']
 assert river['parallel_numbers_increase_downstream'] and river['perpendicular_numbers_increase_away_from_bank']
 for field in ['flow_text','numbering_text','twentieth_century_infrastructure','reconnection_ideal']:
  assert len(river[field])>20 and river[field]in C
 assert river['flow_direction'].replace('_',' ')in river['flow_text']
 assert river['parallel_answer'].rstrip('.').lower()in river['numbering_text'].lower()
 assert 'parallel'in river['numbering_text'] and 'perpendicular'in river['numbering_text']
 assert 'road'in river['twentieth_century_infrastructure'] and 'car parks'in river['twentieth_century_infrastructure']
 assert dict(qs[8]['options'])[qs[8]['answer']]==river['parallel_answer']
 assert river['parallel_answer']=={'west_to_east':'Towards the east.','east_to_west':'Towards the west.','north_to_south':'Towards the south.','south_to_north':'Towards the north.'}[river['flow_direction']]
 assert river['infrastructure_answer']==dict(qs[9]['options'])[qs[9]['answer']]
 forecast=d['forecast'];paras=sections[3]['units'][0].split('\n\n');assert len(paras)==6
 assert forecast['capability']in paras[0] and forecast['sensor_to_model_mechanism']in paras[3] and forecast['network_mechanism']in paras[4]
 assert '**imperative**'in paras[4] and 'paragraph 5'in qs[13]['stem'] and 'imperative'in qs[13]['stem']
 assert 'paragraph 4'in qs[12]['stem'] and dict(qs[13]['options'])[qs[13]['answer']]=='Essential.'
 assert paras[-1].lower().startswith(('if ','should '))
 assert forecast['prediction']in paras[-1] and forecast['conditional_outlook_not_proven_performance'] and forecast['no_exact_accuracy_or_lives_saved_claim']
 assert forecast['imagined_proposal_not_current_product_or_road_safety_advice']
 assert d['fictional_caves_people_city_and_future_system'] and len(d['answer_evidence'])==15
 assert [q['number']for q in qs]==list(range(1,16)) and [q['operation']for q in qs]==OPERATIONS
 for q,e in zip(qs,d['answer_evidence']):
  part='A'if q['number']<4 else'B'if q['number']<8 else'C'if q['number']<12 else'D';sec=sections['ABCD'.index(part)]
  assert q['materialLabel']==part and q['points']==2.5 and q['stem'].startswith(part+'组 · ')
  assert [p[0]for p in q['options']]==list('ABCD') and q['answer']in list('ABCD')
  assert len({p[1].strip().casefold()for p in q['options']})==4 and all(p[1].strip()for p in q['options'])
  reasons=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(reasons)==set('ABCD') and all(reasons.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']]
  assert len(e['evidence'])>20 and e['evidence']in'\n\n'.join(sec['units'])
 assert '15'in d['instruction'] and '37.5分'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 cfg=dict(c,subgroups=[{k:x[k]for k in ['label','responses','material_units','genre']}for x in s['subgroups']])
 return render(sections,cfg)

def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s)
 assert a['student_passage']==passage and g['questions']==d['questions'] and not g['requiredPassageImages']
 assert a['body_load_text']==body_text(d) and a['subgroup_response_counts']==[3,4,4,4] and a['subgroup_material_units']==[4,1,1,1]
 assert a['friendship']==d['friendship'] and a['river']==d['river'] and a['forecast']==d['forecast']
 assert len(a['question_candidate_audit'])==60
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(t.split('：',1)for t in q['rationale'].split('；'))
  assert [(r['label'],r['text'])for r in rows]==[tuple(p)for p in q['options']]
  assert all(r['reason']==why[r['label']]and r['is_best']==(r['label']==q['answer'])for r in rows)
 assert 'A4'in g['passageHtml'] and '<strong>imperative</strong>'in g['passageHtml'] and d['sections'][0]['intro']in g['passageHtml'] and a['source_original_key_not_gold']
 return True
