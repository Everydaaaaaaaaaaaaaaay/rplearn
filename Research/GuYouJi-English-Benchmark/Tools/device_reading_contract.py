"""Whole G8 shared device-picture3 plus six-paragraph narrative4/report4."""
import base64,hashlib,html,json,re,xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref
from check_junior_picture_optional_boundary import validate as validate_boundary
from showcase_rich_reading import material_view

OPS=['shared_device_picture_need']*3+['peer_choice_motivation','club_meeting_emotion','after_entry_action','identity_not_popularity_lesson','opening_example_purpose','paragraph3_context_phrase','conditional_social_practice_risk','balanced_report_title']
DESCRIPTIONS={'rope':'两根长手柄由弯曲绳线相连，旁有数字屏','waterer':'水杯、控制器和连至两盆植物的细管','scannerpen':'纸页、斜置笔状物和有线框显示的手机','printer':'圆角小盒从槽口伸出一条带图形和线条的纸带'}
def digest(t):return hashlib.sha256(t.encode()).hexdigest()
def device_grid_alt(layout):return '四设备候选图：'+'；'.join(k+'为'+DESCRIPTIONS[role]for k,role in zip('ABCD',layout))
def device_svg(role,colour):
 if role=='rope':
  return '<g stroke="#334d4d" stroke-width="3" stroke-linejoin="round"><path d="M43 112C-4 205 176 206 129 112" fill="none"/><rect x="29" y="25" width="28" height="104" rx="12" fill="'+colour+'"/><rect x="115" y="25" width="28" height="104" rx="12" fill="'+colour+'"/><path d="M36 51H50M122 51H136"/><rect x="181" y="28" width="65" height="125" rx="10" fill="#e4edf0"/><rect x="190" y="45" width="47" height="78" fill="white"/><circle cx="214" cy="138" r="5" fill="white"/></g><text x="194" y="79" font-family="monospace" font-size="20" fill="#254648">026</text><path d="M199 101H228M199 109H220" stroke="#8aa3aa" stroke-width="2"/>'
 if role=='waterer':
  return '<g stroke="#334d4d" stroke-width="3" stroke-linejoin="round"><path d="M18 73H63V145Q63 156 53 156H28Q18 156 18 145Z" fill="#cfedf0"/><path d="M20 105H61V143Q61 153 53 153H28Q20 153 20 143Z" fill="#8cc3d7" stroke="none"/><path d="M41 91V53H159V84M125 53H226V84" fill="none" stroke="#76a1aa" stroke-width="5"/><path d="M124 128H167L160 163H131ZM202 128H245L238 163H209Z" fill="#c9ac87"/><path d="M145 130V80M145 106Q113 103 123 81Q147 81 145 106M145 116Q177 111 169 90Q145 92 145 116M224 130V81M224 105Q194 106 199 83Q224 82 224 105M224 117Q253 112 247 91Q224 94 224 117" fill="#bad4a5"/><rect x="81" y="153" width="108" height="37" rx="8" fill="'+colour+'"/><rect x="90" y="160" width="71" height="22" rx="3" fill="#edf4e9"/><circle cx="175" cy="171" r="6" fill="#edf4e9"/></g><text x="96" y="176" font-family="monospace" font-size="15" fill="#254648">08:00</text>'
 if role=='printer':
  return '<g stroke="#334d4d" stroke-width="3" stroke-linejoin="round"><rect x="63" y="28" width="142" height="116" rx="23" fill="'+colour+'"/><path d="M66 88H203" fill="none"/><circle cx="134" cy="59" r="23" fill="#5d7778"/><path d="M91 119H179V191L168 184L157 191L146 184L135 191L124 184L113 191L102 184L91 191Z" fill="#fffdf5"/><path d="M105 158H165M105 168H154M105 178H162" fill="none" stroke-width="2"/><path d="M122 129L135 122L148 129L135 145Z" fill="#c7d8de" stroke-width="2"/><circle cx="188" cy="106" r="5" fill="#dce6c7"/></g>'
 if role=='scannerpen':
  return '<g stroke="#334d4d" stroke-width="3" stroke-linejoin="round"><path d="M16 91Q64 78 104 92Q141 78 174 91V188Q141 176 104 188Q64 176 16 188Z" fill="#fffdf4"/><path d="M104 93V185M29 108H84M29 122H88M29 137H82M29 152H85M119 108H158M119 123H160M119 138H157M119 153H157" fill="none" stroke-width="2"/><rect x="193" y="21" width="62" height="118" rx="9" fill="#d9e7ec"/><rect x="201" y="37" width="46" height="74" fill="white"/><path d="M208 52H239M208 63H237M208 74H239M208 85H230" fill="none" stroke="#93aab1" stroke-width="2"/><circle cx="224" cy="124" r="5" fill="white"/><path d="M109 139L149 53L166 61L126 147L111 157Z" fill="'+colour+'"/><path d="M109 139L126 147L111 157Z" fill="#b87972"/><path d="M134 143L159 151" stroke="#d09a92" stroke-width="5"/></g>'
 raise ValueError(role)
def device_grid_svg(layout,colour):
 assert sorted(layout)==sorted(DESCRIPTIONS)
 panels=[]
 for i,(lab,role)in enumerate(zip('ABCD',layout)):
  x=10+(i%2)*300;y=10+(i//2)*252
  panels.append(f'<g data-device="{role}" transform="translate({x} {y})"><rect width="290" height="242" rx="12" fill="#f7f8f2" stroke="#879b92"/><text x="14" y="27" font-family="Arial,sans-serif" font-size="20" font-weight="bold" fill="#253e38">{lab}</text><g transform="translate(12 38)">'+device_svg(role,colour)+'</g></g>')
 return '<svg xmlns="http://www.w3.org/2000/svg" width="610" height="514" viewBox="0 0 610 514"><rect width="610" height="514" fill="white"/>'+''.join(panels)+'</svg>\n'
def body_text(d):return '\n\n'.join([p['name']+' '+p['text']for p in d['profiles']]+[d['B_title']]+d['B_paragraphs']+d['C_paragraphs'])
def material(d):
 figure=lambda role:'!['+next(m for m in d['media']if m['role']==role)['alt']+']('+next(m for m in d['media']if m['role']==role)['asset']['path']+')'
 A='### A组（第1—3题）\n\n'+figure('device_grid')
 for i,p in enumerate(d['profiles']):A+='\n\n#### '+str(i+1)+'. '+p['name']+'\n\n'+figure('profile'+str(i+1))+'\n\n'+p['text']
 return A+'\n\n### B组（第4—7题）\n\n#### '+d['B_title']+'\n\n'+'\n\n'.join(d['B_paragraphs'])+'\n\n### C组（第8—11题）\n\n'+'\n\n'.join(d['C_paragraphs'])
def render_phrase(passage,a):
 marker='<strong>'+html.escape(a['queried_phrase'])+'</strong>';assert passage.count(marker)==1
 return passage.replace(marker,'<u>'+html.escape(a['queried_phrase'])+'</u>',1)
def validate(d,b,s):
 review=json.loads(load_ref(b['source_index']).read_text());validate_boundary(s,json.loads(load_ref(review['previous_reconciliation']).read_text()))
 assert b['task_mode']=='junior_shared_device_picture_reading11' and b['source_record_sha256']==digest(json.dumps(s,sort_keys=True,ensure_ascii=False))
 assert d['grade']==b['level']==s['level']==8 and d['family']==b['family']==s['kind']=='mixed_closed_reading'
 assert d['source_binding']==b['id'] and d['source_group_id']==b['source_group_id']==s['id']
 cfg=s['configuration'];assert cfg['response_distribution']==[3,4,4] and cfg['material_unit_distribution']==[3,1,1] and cfg['options_each_by_subgroup']==[4,4,4]
 assert cfg['A_each_entry_once_explicit']is False and cfg['selected_objective_points']==22 and cfg['umbrella_reading_points32_not_selected22']
 assert d['source_reuse_ban_not_invented'] and d['old_matching3_not_whole11'] and d['fictional_schools_people_and_survey_not_real_study']
 assert len(d['profiles'])==3 and sorted(d['device_layout'])==sorted(DESCRIPTIONS)
 assert [m['role']for m in d['media']]==['device_grid','profile1','profile2','profile3']
 assert d['media'][0]['alt']==device_grid_alt(d['device_layout']) and load_ref(d['media'][0]['asset']).read_text()==device_grid_svg(d['device_layout'],d['device_colour'])
 for i,m in enumerate(d['media'][1:],1):
  assert m['role']=='profile'+str(i) and m['alt']=='人物'+str(i)+'头像示意'
  svg=ET.fromstring(load_ref(m['asset']).read_text());assert svg.attrib['viewBox']=='0 0 68 76'
 assert len(d['B_paragraphs'])==len(d['C_paragraphs'])==6 and all(p.strip()and'\n'not in p for p in d['B_paragraphs']+d['C_paragraphs'])
 for part,glosses in [('B',d['B_glosses']),('C',d['C_glosses'])]:
  assert len(glosses)==(4 if part=='B'else 5) and len({en for en,zh in glosses})==len(glosses)
  text='\n'.join(d[part+'_paragraphs']);assert len(re.findall('[\u3400-\u9fff]',text))==sum(len(zh)for en,zh in glosses)
  assert all(text.count(en+' ('+zh+')')==1 for en,zh in glosses)
 assert d['narrative']['no_absence_no_actual_performance_evidence']in d['B_paragraphs'][5] and d['narrative']['entry_request_evidence']in d['B_paragraphs'][4]
 assert d['narrative']['fitin_evidence']in d['B_paragraphs'][1] and d['narrative']['preferred_club']!=d['narrative']['initial_club']
 assert '**'+d['queried_phrase']+'**'in d['C_paragraphs'][2] and d['queried_phrase']in d['questions'][8]['stem'] and 'Paragraph 3'in d['questions'][8]['stem']
 survey=d['survey'];n=survey['sample_size'];assert n>0 and n%12==0
 assert survey['ever_count']==n*3//4 and survey['social_count']==survey['serious_instead_count']==n//3 and survey['distrust_count']==n//2
 assert all(str(v)in d['C_paragraphs'][1]for k,v in survey.items()if k in['sample_size','ever_count','social_count','serious_instead_count','distrust_count'])
 assert survey['same_total_denominator_and_overlap_evidence']in d['C_paragraphs'][1] and survey['selfreport_not_causal_evidence']in d['C_paragraphs'][2]
 assert survey['conditional_risk_evidence']in d['C_paragraphs'][4] and survey['balanced_view_evidence']in d['C_paragraphs'][5]
 assert d['source_inline_gloss_counts_bound']==[4,5] and d['source_reference_underline_missing_but_author_target_explicit']
 source=json.loads(load_ref(s['source_projection']).read_text())
 expected={'B':[['debate','辩论'],['trophy','奖杯'],['fit in','融入'],['switch','调换']],'C':[['increasingly','渐增地'],['companion','陪伴'],['interactions','互动'],['rapidly','快速地'],['relying','依赖']]}
 assert s['inline_glosses_by_subgroup']==expected
 for part,pairs in expected.items():
  compact=re.sub(r'\s+','',' '.join(source[part+'_body_fragments']))
  assert all(re.sub(r'\s+','',en+'('+zh+')')in compact for en,zh in pairs)
 assert len(d['questions'])==b['responses']==s['responses']==11 and len(d['answer_evidence'])==11
 assert [q['number']for q in d['questions']]==list(range(1,12)) and [q['operation']for q in d['questions']]==OPS
 for q,e in zip(d['questions'],d['answer_evidence']):
  assert [k for k,t in q['options']]==list('ABCD') and q['answer']in list('ABCD') and q['points']==2
  assert q['materialLabel']==('A'if q['number']<=3 else'B'if q['number']<=7 else'C')
  assert len({t.strip().casefold()for k,t in q['options']})==4 and all(t.strip()for k,t in q['options'])
  why=dict(x.split('：',1)for x in q['rationale'].split('；'));assert set(why)==set('ABCD') and all(why.values())
  assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']] and e['evidence'] and all(len(t)>15 and t in body_text(d)for t in e['evidence'])
  if q['number']<=3:
   profile=d['profiles'][q['number']-1];assert profile['needs_device']in['waterer','rope','printer'] and profile['need_evidence']in profile['text']
   assert q['answer']=='ABCD'[d['device_layout'].index(profile['needs_device'])] and q['options']==[[k,'图片'+k]for k in'ABCD']
 assert '11题'in d['instruction'] and '22分'in d['instruction'] and '原键非gold'in d['source_notice']
 return material(d)
def check(g,a,b,s):
 d=json.loads(load_ref(a['manuscript']).read_text());assert validate(d,b,s)==a['student_passage'] and a['body_load_text']==body_text(d)
 assert g['questions']==d['questions'] and len(g['requiredPassageImages'])==4 and [i['asset']for i in g['requiredPassageImages']]==[m['asset']for m in d['media']]
 value=d['instruction']+'\n\n'+a['student_passage'];parts=[];cursor=0
 for embed,m,image in zip(re.finditer(r'^!\[([^\]]+)\]\(([^)]+)\)\s*$',value,re.M),d['media'],g['requiredPassageImages']):
  raw=load_ref(m['asset']).read_bytes();svg=ET.fromstring(raw);assert embed[1]==image['alt']==m['alt'] and embed[2]==m['asset']['path']
  assert image['src']=='data:image/svg+xml;base64,'+base64.b64encode(raw).decode() and(image['width'],image['height'])==(int(svg.attrib['width']),int(svg.attrib['height']))
  parts.append(material_view(value[cursor:embed.start()]));parts.append('<figure><img class="passage-image" src="'+image['src']+'" alt="'+html.escape(image['alt'],quote=True)+'" width="'+str(image['width'])+'" height="'+str(image['height'])+'"></figure>');cursor=embed.end()
 parts.append(material_view(value[cursor:]));assert g['passageHtml']==render_phrase(''.join(parts),a)
 assert len(a['question_candidate_audit'])==44 and a['subgroup_response_counts']==[3,4,4] and a['subgroup_material_units']==[3,1,1]
 for q in d['questions']:
  rows=[r for r in a['question_candidate_audit']if r['number']==q['number']];why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  assert[(r['label'],r['text'])for r in rows]==[tuple(o)for o in q['options']]
  assert all(r['is_best']==(r['label']==q['answer'])and r['reason']==why[r['label']]for r in rows)
 return True
