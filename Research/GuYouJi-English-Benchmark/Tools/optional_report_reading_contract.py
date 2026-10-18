"""A complete, separate G7 optional research-report reading3, not optional10."""
import hashlib,html,json
from grade_mode_evidence import load_ref
from check_school_mixed_visual_reading import validate as validate_boundary
from showcase_rich_reading import material_view

def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def body_text(d):return '\n\n'.join(d['paragraphs'])
def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());prior=json.loads(load_ref(review['previous_reconciliation']).read_text());validate_boundary(s,prior)
 assert b['task_mode']=='school_optional_report_reading3' and b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert d['grade']==b['level']==s['level']==7 and d['family']==b['family']==s['kind']=='reading_choice'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 cfg=s['configuration'];assert cfg['response_distribution']==[3] and cfg['selected_objective_points']==6 and cfg['optional_umbrella10_not_selected6'] and cfg['separate_grammar56to59_not_included']
 assert b['responses']==s['responses']==3 and b['options_each']==s['options_each']==3
 assert len(d['paragraphs'])==6 and all(len(p)>120 and '\n'not in p for p in d['paragraphs'])
 assert d['fictional_study_not_real_population_or_causal_evidence'] and d['separate_optional6_not10_or_main22']
 st=d['study'];assert st['sample_size']>0 and st['recall_window_months']==3
 assert str(st['sample_size'])in d['paragraphs'][3] and 'three months'in d['paragraphs'][3]
 assert st['reporting_not_causal']in d['paragraphs'][4] and st['limitation']in d['paragraphs'][5]
 assert len(st['definition_evidence'])==2 and all(t in d['paragraphs'][1]for t in st['definition_evidence'])
 assert st['third_paragraph_purpose_evidence']in d['paragraphs'][2]
 assert len(st['application_evidence'])==2 and all(t in body_text(d)for t in st['application_evidence'])
 qs=d['questions'];assert [q['number']for q in qs]==[1,2,3]
 assert [q['operation']for q in qs]==['report_detail','paragraph3_main_purpose','bounded_report_application']
 assert len(d['answer_evidence'])==3
 for q,e in zip(qs,d['answer_evidence']):
  assert q['points']==2 and q['materialLabel']=='XI' and [o[0]for o in q['options']]==list('ABC') and q['answer']in list('ABC')
  assert len({t.casefold().strip()for k,t in q['options']})==3 and all(t.strip()for k,t in q['options'])
  why=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(why)==set('ABC') and all(why.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']] and e['evidence'] and all(len(t)>20 and t in body_text(d)for t in e['evidence'])
 assert '6分'in d['instruction'] and '3题'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 return body_text(d)
def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());body=validate(d,b,s)
 assert a['student_passage']==a['body_load_text']==body and a['study']==d['study']
 assert g['questions']==d['questions'] and not g['requiredPassageImages']
 assert g['passageHtml']==material_view(d['instruction']+'\n\n'+body)
 assert a['report_paragraphs']==6 and len(a['question_candidate_audit'])==9
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  assert[(r['label'],r['text'])for r in rows]==[tuple(o)for o in q['options']]
  assert all(r['is_best']==(r['label']==q['answer'])and r['reason']==why[r['label']]for r in rows)
 return True
