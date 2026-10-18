"""Keep complete G7 calendar/four-picture/prose/three-poem reading15 inputs."""
import calendar,hashlib,html,json,re
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref
from check_school_mixed_visual_reading import validate as validate_boundary
from senior_reading_contract import render
from showcase_rich_reading import material_view
from quality_review_images import check_option_images,without_derived_images

OPERATIONS=['calendar_ordinal_weekday','calendar_text_pronoun','calendar_crossplace_detail','school_detail','school_text_pronoun','four_scene_picture_choice','learning_listening_before_speaking','learning_repeated_practice','learning_early_language_time','learning_limited_practice_reason','poem_bedtime','poem_addressee','poem_contact_detail','poem_helpful_character','three_poems_shared_theme']
def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def calendar_table(c):
 weeks=calendar.Calendar(firstweekday=6).monthdayscalendar(c['year'],c['month']);return '| Sunday | Monday | Tuesday | Wednesday | Thursday | Friday | Saturday |\n|---|---|---|---|---|---|---|\n'+'\n'.join('| '+' | '.join(str(x)if x else''for x in week)+' |'for week in weeks)
def poem_text(poem):return '\n\n'.join('\n'.join(stanza)for stanza in poem['stanzas'])
def glossary_text(d):return '| Word | Meaning |\n|---|---|\n'+'\n'.join('| '+a+' | '+b+' |'for a,b in d['glossary'])
def body_text(d):return '\n\n'.join(t for s in d['sections']for t in([s['intro']]if s.get('intro')else[])+s['units'])+'\n\n'+'\n'.join(a+' '+b for a,b in d['glossary'])
def student_material(d,s):
 cfg=dict(s['configuration'],subgroups=[{k:g[k]for k in ['label','responses','material_units','genre']}for g in s['subgroups']]);sections=[dict(x)for x in d['sections']];c=d['calendar'];sections[0]['units']=[sections[0]['units'][0]+'\n\n#### '+calendar.month_name[c['month']]+' '+str(c['year'])+'\n\n'+calendar_table(c)]
 return render(sections,cfg)+'\n\n#### Word help\n\n'+glossary_text(d)
def render_poem_lines(passage,audit):
 for poem in audit['poems']:
  raw=poem_text(poem);before=material_view(raw);assert passage.count(before)==1
  after='<div class="reading-poem" lang="en">'+''.join('<p>'+'<br>'.join(html.escape(line)for line in stanza)+'</p>'for stanza in poem['stanzas'])+'</div>'
  passage=passage.replace(before,after,1)
 assert passage.count('<div class="table-scroll">')==2
 return passage.replace('<div class="table-scroll">','<div class="table-scroll calendar-reading">',1)
def scene_svg(scene):
 """Four illustrated people, distinguished by age/hair/glasses and branch position."""
 branch=scene['branch_person'];glasses=scene['glasses_person'];palette=scene['palette'];ground=[p for p in ['maths','sports','english','pupil']if p!=branch]
 positions={p:(x,176 if p=='pupil'else 158,False)for p,x in zip(ground,[45,105,245])};positions[branch]=(202,74 if branch=='pupil'else 62,True)
 out=['<svg xmlns="http://www.w3.org/2000/svg" width="300" height="240" viewBox="0 0 300 240">','<rect width="300" height="240" fill="#fff"/>','<path d="M155 208V65M155 100H245" fill="none" stroke="#8b6746" stroke-width="14" stroke-linecap="round"/>','<path d="M15 72Q8 36 54 29Q65 1 104 23Q133 1 164 23Q208 5 226 27Q278 19 285 62Q297 98 267 116H34Q8 107 15 72Z" fill="#daead7" stroke="#597755" stroke-width="3"/>','<path d="M155 208V70M155 104H245" fill="none" stroke="#8b6746" stroke-width="12" stroke-linecap="round"/>','<path d="M10 224H290" stroke="#6e8962" stroke-width="3"/>']
 for role in ['maths','sports','english','pupil']:
  x,y,seated=positions[role];small=role=='pupil';scale=.72 if small else 1;colour=palette[role]
  out.append(f'<g data-role="{role}" data-branch="{str(seated).lower()}" data-glasses="{str(role==glasses).lower()}" transform="translate({x} {y}) scale({scale})">')
  if role=='english':out.append('<path d="M-13 8Q-18-16 0-17Q18-16 13 8L11 26H-11Z" fill="#594c42"/>')
  out.append('<circle cx="0" cy="0" r="12" fill="#f2d0b7" stroke="#3f4240" stroke-width="2"/>')
  if role=='pupil':out.append('<path d="M-13-5Q-7-18 9-11L15-4H-13Z" fill="#7498ba" stroke="#3f4240" stroke-width="1.5"/>')
  elif role!='english':out.append('<path d="M-11-4Q-10-15 3-12Q12-12 12-3" fill="#4e4a43"/>')
  if role==glasses:out.append('<rect x="-11" y="-3" width="9" height="6" rx="1" fill="#181f25"/><rect x="2" y="-3" width="9" height="6" rx="1" fill="#181f25"/><path d="M-2-1H2" stroke="#181f25" stroke-width="2"/>')
  else:out.append('<circle cx="-4" cy="0" r="1.4" fill="#303a3b"/><circle cx="4" cy="0" r="1.4" fill="#303a3b"/>')
  out.append('<path d="M-4 6Q0 9 4 6" fill="none" stroke="#8b594c" stroke-width="1.4"/>')
  out.append(f'<path d="M-10 14H10L15 42H-15Z" fill="{colour}" stroke="#3f4240" stroke-width="2"/>')
  out.append('<path d="M-10 18L-18 38M10 18L18 38" fill="none" stroke="#3f4240" stroke-width="4" stroke-linecap="round"/>')
  if seated:out.append('<path d="M-7 42L-7 53L5 59M7 42L17 48L18 64" fill="none" stroke="#3f4240" stroke-width="5" stroke-linecap="round"/>')
  else:out.append('<path d="M-7 42V62M7 42V62" fill="none" stroke="#3f4240" stroke-width="5" stroke-linecap="round"/>')
  out.append('</g>')
 out.append('</svg>');return ''.join(out)

def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());prior=json.loads(load_ref(review['previous_reconciliation']).read_text());validate_boundary(s,prior)
 assert b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False)) and b['task_mode']=='school_calendar_picture_poem_reading15'
 assert d['grade']==b['level']==s['level']==7 and d['family']==b['family']==s['kind']=='reading_choice'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 assert b['responses']==s['responses']==15 and b['options_each']==s['options_each']==4
 assert s['configuration']['response_distribution']==[3,3,4,5] and s['configuration']['selected_objective_points']==30
 sections=d['sections'];qs=d['questions'];assert [x['label']for x in sections]==list('ABCD')
 assert [x['response_numbers']for x in sections]==[list(range(1,4)),list(range(4,7)),list(range(7,11)),list(range(11,16))]
 for sec,src in zip(sections,s['subgroups']):assert sec['genre']==src['genre'] and len(sec['units'])==src['material_units']
 c=d['calendar'];assert c['weekday']==6 and c['ordinal']in[1,2,3,4]
 dates=[day for day in range(1,calendar.monthrange(c['year'],c['month'])[1]+1)if calendar.weekday(c['year'],c['month'],day)==c['weekday']]
 assert c['answer_day']==dates[c['ordinal']-1] and dict(qs[0]['options'])[qs[0]['answer']]==calendar.month_name[c['month']]+' '+str(c['answer_day'])+'.'
 assert calendar.month_name[c['month']]in c['rule_text'] and str(c['year'])in c['rule_text'] and ['first','second','third','fourth'][c['ordinal']-1]+' Sunday'in c['rule_text']
 assert c['rule_text']in sections[0]['units'][0] and d['calendar_pronoun_evidence']in sections[0]['units'][0]
 assert '**'+d['school_pronoun_target']+'**'in sections[1]['units'][0] and d['school_pronoun_target']in qs[4]['stem']
 assert d['learning_account_not_experiment_or_universal_child_development_evidence'] and d['fictional_calendar_school_learning_and_poems']
 assert len(d['poems'])==3 and len(d['glossary'])==4 and [a for a,b in d['glossary']]==['feed','fur','sweep','count']
 assert sections[3]['units']==[poem_text(p)for p in d['poems']] and all(len(p['stanzas'])>=2 and all(len(st)>=3 and all(line.strip()for line in st)for st in p['stanzas'])for p in d['poems'])
 assert all(re.search(r'\b'+w+r'\b','\n'.join(sections[3]['units']))for w,meaning in d['glossary'])
 assert len(d['answer_evidence'])==15 and [q['number']for q in qs]==list(range(1,16)) and [q['operation']for q in qs]==OPERATIONS
 assert list(d['scene_options'])==list('ABCD') and [q['number']for q in qs if q.get('optionImageAssets')]==[6]
 truth={}
 for label,scene in d['scene_options'].items():
  assert scene['branch_person']in ['maths','sports','english','pupil'] and scene['glasses_person']in ['maths','sports','english','pupil']
  asset=qs[5]['optionImageAssets'][label];assert load_ref(asset).read_text()==scene_svg(scene)
  truth[label]=scene['branch_person']=='sports'and scene['glasses_person']=='maths'
 assert [k for k,v in truth.items()if v]==[qs[5]['answer']] and qs[5]['pictureColumns']==2
 assert len({r['sha256']for r in qs[5]['optionImageAssets'].values()})==4
 for q,e in zip(qs,d['answer_evidence']):
  part='A'if q['number']<4 else'B'if q['number']<7 else'C'if q['number']<11 else'D';sec=sections['ABCD'.index(part)]
  assert q['materialLabel']==part and q['points']==2 and q['stem'].startswith(part+'组 · ') and [x[0]for x in q['options']]==list('ABCD') and q['answer']in list('ABCD')
  if q['number']==6:assert all(not t for k,t in q['options']) and list(q['optionImageAssets'])==list('ABCD')
  else:assert len({t.strip().casefold()for k,t in q['options']})==4 and all(t.strip()for k,t in q['options'])
  why=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(why)==set('ABCD') and all(why.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']] and len(e['evidence'])>20 and e['evidence']in'\n\n'.join(sec['units'])
 assert '15'in d['instruction'] and '30分'in d['instruction'] and '虚构'in d['instruction'] and '原键非gold'in d['source_notice']
 return student_material(d,s)

def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s);assert passage==a['student_passage'] and not g['requiredPassageImages']
 assert without_derived_images(g['questions'])==d['questions'] and check_option_images(g)==4 and a['body_load_text']==body_text(d)
 assert g['passageHtml']==render_poem_lines(material_view(d['instruction']+'\n\n'+passage),a)
 assert a['poems']==d['poems'] and a['scene_options']==d['scene_options'] and a['subgroup_response_counts']==[3,3,4,5]
 assert g['passageHtml'].count('class="reading-poem"')==3 and g['passageHtml'].count('<br>')==sum(len(st)-1 for p in d['poems']for st in p['stanzas'])
 assert '<div class="table-scroll calendar-reading">'in g['passageHtml'] and len(a['question_candidate_audit'])==60
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  assert[(r['label'],r['text'])for r in rows]==[tuple(o)for o in q['options']]
  assert all(r['is_best']==(r['label']==q['answer'])and r['reason']==why[r['label']]for r in rows)
 return True
