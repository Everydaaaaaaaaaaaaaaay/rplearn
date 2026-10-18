"""Source-bound activity-bank3 plus narrative4 plus explanation4, closed11."""
import base64,hashlib,html,json,re,textwrap,xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref
from check_school_mixed_visual_reading import validate as validate_boundary
from showcase_rich_reading import material_view

OPERATIONS=['activity_need_match']*3+['narrative_selected_detail','narrative_emotion','narrative_reluctance_reason','narrative_lesson']+['explanation_detail','paragraph4_phrase_meaning','last_paragraph_heading','author_context_view']
def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def svgwrap(w,h,body):return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="{w}" height="{h}" fill="#fff"/>'+body+'</svg>\n'
def icon(kind,x,y):
 shapes={'music':'<path d="M12 8V35M12 8L38 3V30M12 15L38 10" fill="none"/><ellipse cx="5" cy="36" rx="8" ry="5"/><ellipse cx="31" cy="31" rx="8" ry="5"/>','nature':'<path d="M23 42V5M23 26Q-4 24 4 8Q27 7 23 26M23 34Q48 33 44 16Q21 15 23 34" fill="#b9d1a5"/>','craft':'<path d="M5 5H37V39H5Z" fill="#e2bd80"/><path d="M10 31L37 4L43 10L16 37Z" fill="#acc5d0"/>','sport':'<circle cx="23" cy="8" r="6"/><path d="M23 15L18 31L5 40M18 31L34 42M22 20L36 25L43 15M21 21L8 23" fill="none"/>'}
 return f'<g transform="translate({x} {y})" stroke="#405950" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+shapes[kind]+'</g>'
def grid_svg(cards):
 out=[]
 for index,c in enumerate(cards):
  x=10+(index%2)*300;y=10+(index//2)*268
  out.append(f'<rect x="{x}" y="{y}" width="290" height="258" rx="10" fill="#f3f5ee" stroke="#809287"/>')
  out.append(icon(c['icon'],x+232,y+12))
  lines=[(c['label']+'. '+c['title'],True)]+[(line,False)for line in textwrap.wrap(c['text'],31)]+[(c['time'],False),(c['place'],False)]
  assert len(lines)<=11
  for n,(line,bold)in enumerate(lines):
   tx=x+12;ty=y+27 if n==0 else y+73+(n-1)*18
   out.append(f'<text x="{tx}" y="{ty}" font-family="Arial,sans-serif" font-size="15"'+(' font-weight="bold"'if bold else'')+'>'+html.escape(line)+'</text>')
 return svgwrap(610,546,''.join(out))
def face_svg(n):
 colours=['#a8c4c2','#d6b99a','#bfc5a0'];hair=['M17 28Q17 3 34 7Q51 10 49 28L44 20L22 24Z','M16 29Q13 4 33 5Q55 4 51 35L49 51H17Z','M17 26Q16 5 34 6Q53 7 50 27L42 20L22 21Z'][n]
 return svgwrap(68,76,'<path d="'+hair+'" fill="#514b43"/><ellipse cx="34" cy="30" rx="16" ry="20" fill="#e8c5aa" stroke="#405950"/><circle cx="28" cy="29" r="1.7"/><circle cx="40" cy="29" r="1.7"/><path d="M29 39Q34 43 39 39" fill="none" stroke="#80594b"/><path d="M10 76V62Q13 49 28 49H40Q55 49 58 62V76Z" fill="'+colours[n]+'" stroke="#405950"/>')
def glossary_svg():
 return svgwrap(400,150,'<g stroke="#405950" stroke-width="3" fill="#c2d6dc"><path d="M30 31H148V90Q148 105 130 105H48Q30 105 30 90Z"/><path d="M30 43H13V67H30M148 43H165V67H148M49 29Q90 3 129 29" fill="none"/><rect x="220" y="36" width="143" height="70" rx="7"/><path d="M220 59H363M237 81H249M263 81H275M289 81H301" fill="none"/><ellipse cx="254" cy="42" rx="17" ry="5"/><ellipse cx="326" cy="42" rx="17" ry="5"/></g><g font-family="Arial,sans-serif" font-size="18" fill="#253c34"><text x="72" y="136">pot</text><text x="270" y="136">stove</text></g>')
def orchard_svg(colour):
 return svgwrap(440,230,'<path d="M28 207H416" stroke="#79906d" stroke-width="3"/><path d="M134 205V54M134 102L78 68M134 121L199 73" fill="none" stroke="#8d6e50" stroke-width="16"/><path d="M40 71Q31 5 99 19Q151-7 191 20Q259 10 249 71Q263 127 202 135H84Q31 123 40 71" fill="#d8e5c9" stroke="#79906d" stroke-width="3"/>'+''.join(f'<circle cx="{x}" cy="{y}" r="9" fill="{colour}"/>'for x,y in[(75,51),(171,40),(218,88),(111,103)])+'<g stroke="#405950" stroke-width="3"><circle cx="280" cy="75" r="18" fill="#e8c5aa"/><path d="M263 96H297L308 160H252Z" fill="#a9c3cb"/><path d="M266 160V206M293 160V206M263 106L224 83M299 110L321 139" fill="none"/><circle cx="352" cy="119" r="14" fill="#e8c5aa"/><path d="M341 137H363L372 177H332Z" fill="#d8c28f"/><path d="M340 177V207M362 177V207" fill="none"/><path d="M318 179H386L377 210H328Z" fill="#d4b685"/></g>')
def body_text(d):
 return '\n\n'.join([d['banner']]+[' '.join(c[k]for k in ['label','title','text','time','place'])for c in d['cards']]+[p['name']+' '+p['text']for p in d['profiles']]+[d['B_title']]+d['B_paragraphs']+['pot stove']+[d['C_intro']]+[v for sec in d['C_sections']for v in[sec['heading']]+sec['paragraphs']])
def material(d):
 media=d['media'];img=lambda role:'!['+next(m for m in media if m['role']==role)['alt']+']('+next(m for m in media if m['role']==role)['asset']['path']+')'
 A='### A组（第1—3题）\n\n'+d['banner']+'\n\n'+img('activity_grid')
 for i,p in enumerate(d['profiles']):A+='\n\n#### '+str(i+1)+'. '+p['name']+'\n\n'+img('profile'+str(i+1))+'\n\n'+p['text']
 B='### B组（第4—7题）\n\n#### '+d['B_title']+'\n\n'+img('orchard')+'\n\n'+'\n\n'.join(d['B_paragraphs'][:6])+'\n\n'+img('pot_stove_gloss')+'\n\n'+'\n\n'.join(d['B_paragraphs'][6:])
 C='### C组（第8—11题）\n\n'+d['C_intro']+'\n\n'+'\n\n'.join('#### '+sec['heading']+'\n\n'+'\n\n'.join(sec['paragraphs'])for sec in d['C_sections'])
 return A+'\n\n'+B+'\n\n'+C
def render_target(passage,a):
 marker='<strong>'+html.escape(a['underlined_phrase'])+'</strong>';assert passage.count(marker)==1
 return passage.replace(marker,'<u>'+html.escape(a['underlined_phrase'])+'</u>',1)
def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());validate_boundary(s,json.loads(load_ref(review['previous_reconciliation']).read_text()))
 assert b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False)) and b['task_mode']=='school_closed_mixed_reading11'
 assert d['grade']==b['level']==s['level']==7 and d['family']==b['family']==s['kind']=='mixed_closed_reading'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 assert b['responses']==s['responses']==11 and b['options_per_response']==[4]*3+[3]*8
 cfg=s['configuration'];assert cfg['response_distribution']==[3,4,4] and cfg['selected_objective_points']==22 and cfg['umbrella_reading_points30_not_selected22']
 assert cfg['material_unit_distribution']==[7,1,1] and cfg['A_each_entry_once_explicit']is False
 assert d['fictional_activities_people_and_plans'] and d['source_reuse_rule_not_invented'] and d['selected22_not_main30']
 assert len(d['cards'])==4 and [c['label']for c in d['cards']]==list('ABCD') and len(d['profiles'])==3
 for p in d['profiles']:
  assert len(p['suitable_card_labels'])==1
  c=next(c for c in d['cards']if c['label']==p['suitable_card_labels'][0]);assert p['matching_evidence']in c['text']
 assert len(d['B_paragraphs'])==12 and d['B_expected_outcome_not_already_won']in d['B_paragraphs'][-1]
 assert [len(sec['paragraphs'])for sec in d['C_sections']]==[1,2,1]
 assert d['C_sections'][-1]['heading']=='____10____'
 assert '**'+d['underlined_phrase']+'**'in d['C_sections'][1]['paragraphs'][1]
 assert d['restricted_project_plans_not_personal_safety_or_disclosure_advice']
 assert [m['role']for m in d['media']]==['activity_grid','profile1','profile2','profile3','orchard','pot_stove_gloss']
 expected=[grid_svg(d['cards'])]+[face_svg(i)for i in range(3)]+[orchard_svg(d['fruit_colour']),glossary_svg()]
 for m,svg in zip(d['media'],expected):assert load_ref(m['asset']).read_text()==svg and m['alt']
 assert d['media'][0]['alt']=='四活动卡：'+'；'.join(' '.join(c[k]for k in ['label','title','text','time','place'])for c in d['cards'])
 assert d['media'][4]['alt']=='虚构果园采果示意：成人、儿童与篮子，非照片'
 qs=d['questions'];assert [q['number']for q in qs]==list(range(1,12)) and [q['operation']for q in qs]==OPERATIONS
 assert len(d['answer_evidence'])==11
 for q,e in zip(qs,d['answer_evidence']):
  size=4 if q['number']<=3 else 3;part='A'if q['number']<=3 else'B'if q['number']<=7 else'C'
  assert q['materialLabel']==part and q['points']==2 and [k for k,t in q['options']]==list('ABCD')[:size] and q['answer']in list('ABCD')[:size]
  assert len({t.strip().casefold()for k,t in q['options']})==size and all(t.strip()for k,t in q['options'])
  why=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(why)==set('ABCD'[:size]) and all(why.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']] and e['evidence'] and all(len(t)>15 and t in body_text(d)for t in e['evidence'])
  if q['number']<=3:assert q['answer']==d['profiles'][q['number']-1]['suitable_card_labels'][0]and q['options']==[[k,'活动'+k]for k in'ABCD']
 assert d['underlined_phrase']in qs[8]['stem'] and 'Paragraph 4'in qs[8]['stem']
 assert '11题'in d['instruction'] and '22分'in d['instruction'] and '原键非gold'in d['source_notice']
 return material(d)
def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());assert validate(d,b,s)==a['student_passage'] and a['body_load_text']==body_text(d)
 assert g['questions']==d['questions'] and len(g['requiredPassageImages'])==6 and '<u>'+html.escape(d['underlined_phrase'])+'</u>'in g['passageHtml']
 assert [x['asset']for x in g['requiredPassageImages']]==[m['asset']for m in d['media']]
 value=d['instruction']+'\n\n'+a['student_passage'];parts=[];cursor=0
 for embed,m,image in zip(re.finditer(r'^!\[([^\]]+)\]\(([^)]+)\)\s*$',value,re.M),d['media'],g['requiredPassageImages']):
  assert embed[1]==image['alt']==m['alt'] and embed[2]==m['asset']['path']
  raw=load_ref(m['asset']).read_bytes();svg=ET.fromstring(raw)
  assert image['src']=='data:image/svg+xml;base64,'+base64.b64encode(raw).decode()
  assert (image['width'],image['height'])==(int(svg.attrib['width']),int(svg.attrib['height']))
  parts.append(material_view(value[cursor:embed.start()]))
  parts.append('<figure><img class="passage-image" src="'+image['src']+'" alt="'+html.escape(image['alt'],quote=True)+'" width="'+str(image['width'])+'" height="'+str(image['height'])+'"></figure>');cursor=embed.end()
 parts.append(material_view(value[cursor:]));assert g['passageHtml']==render_target(''.join(parts),a)
 assert a['subgroup_response_counts']==[3,4,4] and a['subgroup_material_units']==[7,1,1]
 assert len(a['question_candidate_audit'])==36
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  assert[(r['label'],r['text'])for r in rows]==[tuple(o)for o in q['options']]
  assert all(r['is_best']==(r['label']==q['answer'])and r['reason']==why[r['label']]for r in rows)
 return True
