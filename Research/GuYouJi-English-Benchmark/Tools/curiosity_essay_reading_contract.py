"""Whole G8 optional six-paragraph essay reading3, each four choices and five glosses."""
import hashlib,json,re
from grade_mode_evidence import load_ref
from check_junior_picture_optional_boundary import validate as validate_boundary
from showcase_rich_reading import material_view

OPS=['paragraph2_definition_detail','paragraph3_example_purpose','bounded_message_application']
def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def body_text(d):return '\n\n'.join(d['paragraphs'])
def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());prior=json.loads(load_ref(review['previous_reconciliation']).read_text());validate_boundary(s,prior)
 assert b['task_mode']=='junior_optional_curiosity_essay3' and b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert d['grade']==b['level']==s['level']==8 and d['family']==b['family']==s['kind']=='reading_choice'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 cfg=s['configuration'];assert cfg['response_distribution']==[3] and cfg['options_each']==b['options_each']==s['options_each']==4 and cfg['selected_objective_points']==6
 assert cfg['report_paragraphs']==6 and cfg['example_paragraph']==3 and cfg['separate_grammar53to56_4points_excluded']
 source_body=json.loads(load_ref(s['source_projection']).read_text())['optional_body'];source_compact=re.sub(r'\s+','',source_body)
 assert s['inline_glosses']==[['spark','火花'],['gap','差距'],['melts evenly','融化均匀'],['pause','暂停'],['approach','靠近']]
 assert all(re.sub(r'\s+','',en+'('+zh+')')in source_compact for en,zh in s['inline_glosses'])
 assert d['complete_sixparagraph_essay_not_report_template_or_summary'] and d['fictional_examples_not_scientific_or_safety_instruction'] and d['q1_narrowed_to_definition_not_source57broad_dualsupport']
 assert len(d['paragraphs'])==6 and all(len(p)>100 and '\n'not in p for p in d['paragraphs'])
 assert d['definition_evidence']in d['paragraphs'][1] and d['everyday_example_evidence']in d['paragraphs'][2] and d['example_reflection_evidence']in d['paragraphs'][3]
 assert d['social_learning_evidence']in d['paragraphs'][4] and d['application_limit_evidence']in d['paragraphs'][5]
 gloss=d['inline_glosses'];assert len(gloss)==5 and len({en for en,zh in gloss})==5
 assert sum(len(re.findall('[\u3400-\u9fff]',p))for p in d['paragraphs'])==sum(len(zh)for en,zh in gloss)>0
 for en,zh in gloss:assert body_text(d).count(en+' ('+zh+')')==1
 assert 'paragraph 2'in d['questions'][0]['stem'].lower() and 'paragraph 3'in d['questions'][1]['stem'].lower()
 assert len(d['questions'])==b['responses']==s['responses']==3 and len(d['answer_evidence'])==3
 assert [q['number']for q in d['questions']]==[1,2,3] and [q['operation']for q in d['questions']]==OPS
 for q,e in zip(d['questions'],d['answer_evidence']):
  assert q['points']==2 and q['materialLabel']=='X' and [k for k,t in q['options']]==list('ABCD') and q['answer']in list('ABCD')
  assert len({t.strip().casefold()for k,t in q['options']})==4 and all(t.strip()for k,t in q['options'])
  why=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(why)==set('ABCD') and all(why.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']] and e['evidence'] and all(len(t)>20 and t in body_text(d)for t in e['evidence'])
 assert '3题'in d['instruction'] and '6分'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 return body_text(d)
def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());body=validate(d,b,s)
 assert a['student_passage']==a['body_load_text']==body and a['inline_glosses']==d['inline_glosses']
 assert g['questions']==d['questions'] and not g['requiredPassageImages'] and g['passageHtml']==material_view(d['instruction']+'\n\n'+body)
 assert a['essay_paragraphs']==6 and a['example_paragraph']==3 and len(a['question_candidate_audit'])==12
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  assert [(r['label'],r['text'])for r in rows]==[tuple(o)for o in q['options']]
  assert all(r['is_best']==(r['label']==q['answer'])and r['reason']==why[r['label']]for r in rows)
 return True
