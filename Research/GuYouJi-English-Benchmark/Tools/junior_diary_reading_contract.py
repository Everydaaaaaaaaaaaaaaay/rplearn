"""Source-bound G7 whole15: profiles, six-time diary, explanation, fantasy."""
import json
from grade_mode_evidence import load_ref
from check_school_further_reading import validate as validate_boundary
from email_reading_contract import digest
from senior_reading_contract import render,body_text

TIMES=['5 a.m.','7 a.m.','8 a.m.','3 p.m.','9 p.m.','12 a.m. (start of the next day)']
OPERATIONS=['home_design_reason','context_word_meaning','cross_profile_true','diary_initial_feeling','diary_completed_afternoon_action','diary_relationship_inference','diary_title','explanation_publication','explicit_activity_rule','chess_thinking_comparison','writer_recommendation','fantasy_four_event_sequence','fantasy_missing_turn','fantasy_character','fantasy_whole_context_inference']

def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());validate_boundary(s,json.loads(load_ref(review['previous_reconciliation']).read_text()))
 assert b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert b['task_mode']=='school_junior_profiles_diary_fantasy_reading15' and b['author_gate']=='grade7_profiles_diary_fantasy15_v1'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 assert d['grade']==b['level']==s['level']==7 and d['family']==b['family']==s['kind']=='reading_choice'
 c=s['configuration'];assert s['responses']==b['responses']==15 and s['options_each']==b['options_each']==4
 assert c['response_distribution']==[3,4,4,4] and c['material_unit_distribution']==[3,1,1,1]
 assert c['points_each']==2 and c['selected_objective_points']==30
 sections=d['sections'];qs=d['questions'];assert [x['label']for x in sections]==list('ABCD')
 assert [x['response_numbers']for x in sections]==[list(range(1,4)),list(range(4,8)),list(range(8,12)),list(range(12,16))]
 for sec,src in zip(sections,s['subgroups']):
  assert sec['genre']==src['genre'] and len(sec['units'])==src['material_units'] and all(u.strip()for u in sec['units'])
 assert sections[0]['intro'].strip() and all(not x.get('intro')for x in sections[1:])
 assert len(d['home_names'])==len(set(d['home_names']))==3
 assert all(u.startswith(name+'\n')for u,name in zip(sections[0]['units'],d['home_names']))
 assert '**'+d['lexical_target']+'**' in sections[0]['units'][2] and d['lexical_target']in qs[1]['stem']
 diary=d['diary'];assert diary['times']==TIMES and len(diary['entries'])==6 and diary['opening']
 assert sections[1]['units']==[diary['opening']+'\n\n'+'\n\n'.join(t+' — '+e for t,e in zip(TIMES,diary['entries']))]
 assert diary['afternoon_completed_evidence']in diary['entries'][3] and diary['afternoon_completed_not_merely_planned']
 assert 'already' in diary['afternoon_completed_evidence'].lower() and diary['midnight_next_day_explicit']
 activity=d['activity'];assert activity['rule']in sections[2]['units'][0] and activity['comparison']in sections[2]['units'][0]
 assert activity['recommendation']in sections[2]['units'][0] and activity['not_climbing_safety_or_health_instruction']
 fantasy=d['fantasy'];assert sections[3]['units'][0].count('▲')==1 and len(fantasy['events'])==4
 assert set(fantasy['events'])==set('abcd') and sorted(fantasy['order'])==list('abcd')
 assert len(fantasy['evidence'])==4
 text=sections[3]['units'][0];offsets=[text.index(fantasy['evidence'][label])for label in fantasy['order']];assert offsets==sorted(set(offsets))
 assert dict(qs[11]['options'])[qs[11]['answer']]=='-'.join(fantasy['order'])
 assert all(label+'. '+event in qs[11]['stem']for label,event in fantasy['events'].items())
 assert dict(qs[12]['options'])[qs[12]['answer']]==fantasy['missing_turn']
 assert d['fictional_profiles_diary_activity_fantasy'] and len(d['answer_evidence'])==15
 assert [q['number']for q in qs]==list(range(1,16)) and [q['operation']for q in qs]==OPERATIONS
 for q,e in zip(qs,d['answer_evidence']):
  part='A'if q['number']<4 else'B'if q['number']<8 else'C'if q['number']<12 else'D';sec=sections['ABCD'.index(part)]
  assert q['materialLabel']==part and q['points']==2 and q['stem'].startswith(part+'组 · ')
  assert [p[0]for p in q['options']]==list('ABCD') and q['answer']in list('ABCD')
  assert len({p[1].strip().casefold()for p in q['options']})==4 and all(p[1].strip()for p in q['options'])
  reasons=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(reasons)==set('ABCD') and all(reasons.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']]
  assert len(e['evidence'])>20 and e['evidence']in'\n\n'.join(sec['units'])
 assert '15'in d['instruction'] and '30分'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 cfg=dict(c,subgroups=[{k:x[k]for k in ['label','responses','material_units','genre']}for x in s['subgroups']])
 return render(sections,cfg)

def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s)
 assert a['student_passage']==passage and g['questions']==d['questions'] and not g['requiredPassageImages']
 assert a['body_load_text']==body_text(d) and a['subgroup_response_counts']==[3,4,4,4] and a['subgroup_material_units']==[3,1,1,1]
 assert a['diary']==d['diary'] and a['fantasy']==d['fantasy'] and a['activity']==d['activity']
 assert len(a['question_candidate_audit'])==60
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(t.split('：',1)for t in q['rationale'].split('；'))
  assert [(r['label'],r['text'])for r in rows]==[tuple(p)for p in q['options']]
  assert all(r['reason']==why[r['label']]and r['is_best']==(r['label']==q['answer'])for r in rows)
 assert all(t in g['passageHtml']for t in TIMES) and g['passageHtml'].count('▲')==1
 assert sections_intro(d)in g['passageHtml'] and a['source_original_key_not_gold']
 return True

def sections_intro(d):return d['sections'][0]['intro']
