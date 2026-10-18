"""Source-bound grade9 two-article ten-response ABC reading section."""
import hashlib,json,re
from datetime import datetime
from grade_mode_evidence import load_ref
from check_school_further_reading import validate as validate_boundary
from school_reading_contract import material,ranges

OPERATIONS=['email_earliest_sender','email_booking_concern','email_destination_reason','email_final_agreement','email_thread_subject','study_proposed_explanation','study_competition_benefit','study_appearance_detail','study_age_uncertainty','study_publication_section']
def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def email(e):
 return '\n\n'.join(['From: '+e['from'],'To: '+'; '.join(e['to']),'Sent: '+datetime.fromisoformat(e['sent']).strftime('%d %B %Y, %H:%M'),'Subject: '+e['subject'],e['body']])

def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());prior=json.loads(load_ref(review['previous_reconciliation']).read_text());validate_boundary(s,prior)
 assert b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert b['task_mode']=='school_email_chain_study_reading10' and b['author_gate']=='grade9_four_email_study10_v1'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 assert d['grade']==b['level']==s['level']==9 and d['family']==b['family']==s['kind']=='reading_choice'
 assert s['responses']==b['responses']==10 and s['options_each']==b['options_each']==3
 c=s['configuration'];assert c['response_distribution']==[5,5] and c['material_unit_distribution']==[4,1]
 assert c['points_each']==2 and c['selected_objective_points']==20 and s['outer_reading_points30_selected_MC20_notTF10']
 assert [sec['label']for sec in d['sections']]==['A','B']
 for sec,g in zip(d['sections'],s['subgroups']):
  assert sec['genre']==g['genre'] and len(sec['units'])==g['material_units']
 assert d['sections'][0]['response_numbers']==list(range(1,6)) and d['sections'][1]['response_numbers']==list(range(6,11))
 es=d['emails'];assert len(es)==4 and len({e['from']for e in es})==3 and es[0]['from']==es[-1]['from']
 people={e['from']for e in es};assert d['email_times_same_time_zone']
 assert all(set(e['to'])==people-{e['from']}and e['subject'].strip()and len(e['body'])>50 for e in es)
 times=[datetime.fromisoformat(e['sent'])for e in es];assert times==sorted(set(times)) and len({t.date()for t in times})==1
 assert d['sections'][0]['units']==[email(e)for e in es]
 windows=d['proposed_windows'];assert len(windows)==3 and len(set(windows))==3
 avail=d['availability'];assert set(avail)==people and all(set(a)<=set(windows)for a in avail.values())
 common=set(windows)
 for a in avail.values():common&=set(a)
 assert common=={d['agreed_window']} and d['availability_scope_only_proposed_windows']
 qs=d['questions'];assert [q['number']for q in qs]==list(range(1,11)) and [q['operation']for q in qs]==OPERATIONS
 assert dict(qs[0]['options'])[qs[0]['answer']]==es[0]['from']
 assert dict(qs[3]['options'])[qs[3]['answer']]==d['final_agreement_answer_text']
 assert d['final_agreement_evidence']in es[-1]['body'] and d['destination_reason_evidence']in es[1]['body']
 assert d['fictional_mail_places_study_data_not_real_correspondence']
 B=d['sections'][1]['units'][0];study=d['study'];assert study['hypothesis_not_proven_cause'] and study['age_estimate_not_exact']
 assert study['individual_record_not_all_tropical_trees'] and study['not_human_storm_safety_instruction']
 for k in ['hypothesis','benefit','appearance','age_limit']:
  assert len(study[k])>20 and study[k]in B
 assert 'proposed' in qs[5]['stem'] or 'suggested' in qs[5]['stem']
 assert len(d['answer_evidence'])==10
 for q,e in zip(qs,d['answer_evidence']):
  assert q['materialLabel']==('A'if q['number']<6 else'B') and q['points']==2
  assert q['stem'].startswith(q['materialLabel']+'组 · ')
  assert [p[0]for p in q['options']]==list('ABC') and q['answer']in'ABC'
  assert len({p[1].strip().casefold()for p in q['options']})==3
  reasons=dict(t.split('：',1)for t in q['rationale'].split('；'));assert set(reasons)==set('ABC') and all(reasons.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']]
  assert len(e['evidence'])>20 and e['evidence']in'\n\n'.join(d['sections'][0 if q['number']<6 else 1]['units'])
 assert '10' in d['instruction'] and '20分'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 cfg=dict(c,subgroups=[{k:g[k]for k in ['label','responses','material_units','genre']}for g in s['subgroups']])
 return material(d['sections'],cfg)

def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s)
 assert a['student_passage']==passage and g['questions']==d['questions'] and not g['requiredPassageImages']
 assert a['emails']==d['emails'] and a['study']==d['study']
 assert a['body_load_text']=='\n\n'.join(u for sec in d['sections']for u in sec['units'])
 assert a['subgroup_response_counts']==[5,5] and a['subgroup_material_units']==[4,1]
 assert len(a['question_candidate_audit'])==30
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']]
  reasons=dict(t.split('：',1)for t in q['rationale'].split('；'))
  assert [(r['label'],r['text'])for r in rows]==[tuple(p)for p in q['options']]
  assert all(r['reason']==reasons[r['label']]and r['is_best']==(r['label']==q['answer'])for r in rows)
 assert all('A'+str(n)in g['passageHtml']for n in range(1,5))
 assert g['passageHtml'].count('From:')==4 and g['passageHtml'].count('To:')==4 and g['passageHtml'].count('Sent:')==4 and g['passageHtml'].count('Subject:')==4
 return True
