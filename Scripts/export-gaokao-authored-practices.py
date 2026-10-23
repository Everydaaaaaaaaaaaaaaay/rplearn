#!/usr/bin/env python3
"""Compose reviewed original groups using the verified national-I exam structure.
Preserve source manuscripts, questions, answer keys and full passage boundaries.
"""
import copy, hashlib, json, re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
def digest(v):return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
manifest=json.loads((ROOT/'Backend/config/learning/originals/catalog.json').read_text())
entries=manifest['units'];practices=[]
presentation={e['sourceHash']:e for e in json.loads((ROOT/'Backend/config/learning/presentation-revisions.json').read_text())['entries']}
def validate(e):
 u=e['unit'];assert digest(u)==e['contentHash'],u['id']
 assert u['authorship']['kind']=='authored' and u['originalGroup'] and not u['beats']
 assert not any(q.get('materialImages') or 'audio' in q for q in u['questions'])
 for q in u['questions']:
  probes=[p for p in e['probes'] if p['questionId']==q['id']];assert {p['outcome'] for p in probes}>={'correct','incorrect'}
 return u
def body(s):
 # Remove only the author's administrative opening, never a passage paragraph.
 parts=s.split('\n\n',1)
 return parts[1] if len(parts)==2 and re.match(r'^(阅读|从A[—–-]G)',parts[0]) else s

def component(e,family,letter=None,first=1,last=None,material=None):
 u=validate(e);last=last or len(u['questions']);qs=copy.deepcopy(u['questions'][first-1:last]);mat=body(material if material is not None else u['originalGroup']['material'])
 suffix=letter.lower() if letter else 'whole';cid=u['id']+'#'+suffix
 for number,q in enumerate(qs,first):
  patch=presentation.get(digest({k:v for k,v in q.items() if k!='id'}))
  if patch and patch.get('options'):
   options={o['id']:o['text'] for o in patch['options']}
   assert set(options)=={o['id'] for o in q['options']}
   for o in q['options']:o['text']=options[o['id']]
  q['id']='authored.'+hashlib.sha256(u['id'].encode()).hexdigest()[:20]+'.'+q['id']
  q['material']=mat
  q['instruction']='Read the complete passage and answer the question.'
  if family=='reading_choice':q['prompt']=re.sub(r'^[A-Z]组 · ','',q['prompt'])
  elif family=='choice_cloze':q['prompt']=f'Choose the best answer for gap {number}.'
  elif family=='shared_insertion':q['prompt']=f'Choose the sentence or heading for gap {number}.'
  else:q['prompt']=f'Complete gap {number}. Use the given word where provided.'
 return dict(id=cid,family=family,questionIds=[q['id'] for q in qs],sourceNumbers=list(range(first,last+1)),sourceUnitId=u['id'],sourceContentHash=e['contentHash'],questions=qs,origin=u)
def add(level,parts,label):
 qs=[q for c in parts for q in c['questions']];key=digest([c['id'] for c in parts])[:16];uid='gaokao.authored.'+level+'.'+key
 minutes=20 if parts[0]['family']=='choice_cloze' else 18 if all(c['family']=='reading_choice' for c in parts) else 16
 first=parts[0]['origin'];unit=copy.deepcopy(first)
 unit.update(id=uid,version=1,level=level,title='高考题型原创 · '+label,summary=f'{label}，共{len(qs)}题，建议约{minutes}分钟。',scene='按照高考题型编写的完整原创练习。',estimatedMinutes=minutes,goalIds=list(dict.fromkeys(q['goalId'] for q in qs)),prerequisiteGoalIds=[],questions=qs)
 unit['originalGroup']=dict(id=uid,family=parts[0]['family'] if len(parts)==1 or all(c['family']=='reading_choice' for c in parts) else 'gaokao_mixed',label='高考题型原创 · '+label,candidateSHA256=digest([c['sourceContentHash'] for c in parts]),authorCheckSHA256=digest(qs),sourceGroupIds=[c['id'] for c in parts],sourceNotice='原创材料与设问，非高考真题。题型及完整结构对照2025年高考全国一卷；原作者审核绑定保留，未声称官方认证或学生实测等值。',material='')
 unit['references']=[dict(sourceId='gaokao.2025.national1',unit='2025年高考英语全国一卷题型结构',pages='笔试阅读及语言运用',alignment='仅参照完整题型、选项和空位结构；本练习正文及设问为原创，不冒充真题。')]+[r for c in parts for r in c['origin']['references']]
 unit['authorship']['reviewedAt']='2026-10-23'
 unit['authorship']['reviewedBy']='LingoTrip题型与完整组卷核验'
 unit['authorship']['reviewNotes']='复用已绑定审核摘要的完整原创稿；按全国一卷结构组织完整题组，未改写答案。不是高考真题，未声称独立教研或学生难度等值。'
 practices.append(dict(kind='authored',unit=unit,contentHash=digest(unit),components=[{k:v for k,v in c.items() if k not in ['questions','origin']} for c in parts]))
for level in ['senior1','senior2','senior3']:
 es=[e for e in entries if e['unit']['level']==level]
 for e in es:
  u=e['unit'];family=u['originalGroup']['family'];qs=u['questions'];mat=u['originalGroup']['material']
  if family=='choice_cloze' and len(qs)==15 and all(q['type']=='choice' and len(q['options'])==4 for q in qs):add(level,[component(e,family)],'完形填空 · 一篇')
  if family=='reading_choice' and len(qs)==15 and not any(q.get('materialImages') for q in qs):
   headings=list(re.finditer(r'^([A-Z])组[（(]第(\d+)[—–−-](\d+)题[）)]$',mat,re.M))
   if [(h[1],int(h[2]),int(h[3])) for h in headings]!=[('A',1,3),('B',4,7),('C',8,11),('D',12,15)]:continue
   cs=[component(e,family,h[1],int(h[2]),int(h[3]),mat[h.end():headings[i+1].start() if i+1<len(headings) else len(mat)].strip()) for i,h in enumerate(headings)]
   for i in (0,2):add(level,cs[i:i+2],'阅读理解 · 两篇')
 insertion=[e for e in es if e['unit']['originalGroup']['family']=='shared_insertion' and len(e['unit']['questions'])==5 and all(q['type']=='choice' and len(q['options'])==7 for q in e['unit']['questions'])]
 if level=='senior1':
  companions=[e for e in es if e['unit']['originalGroup']['family']=='reading_choice' and len(e['unit']['questions'])==4]
  for reading,gaps in zip(companions,insertion):add(level,[component(reading,'reading_choice'),component(gaps,'shared_insertion')],'阅读理解＋七选五')
 else:
  companions=[e for e in es if e['unit']['originalGroup']['family']=='passage_form' and e['unit']['id'].startswith('original.grade'+('11' if level=='senior2' else '12')+'-grammar-')][:3]
  for gaps,grammar in zip(insertion,companions):
   g=grammar['unit'];assert not re.search(r'\n\n[A-C]\n',g['originalGroup']['material'])
   assert all(q['type']=='completion' and ('无提示' not in q['prompt'] or all(len(a.split())==1 for a in q['acceptedAnswers'])) for q in g['questions'])
   add(level,[component(gaps,'shared_insertion'),component(grammar,'passage_form')],'七选五＋语法填空')
result=dict(version=1,standard='gaokao.2025.national1',notice='按高考完整题型编写的原创题；不等同于高考真题。原作者稿和历史数据保持不变。',practices=practices)
(ROOT/'Backend/config/learning/gaokao/authored.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'practices':len(practices),'perLevel':{l:sum(p['unit']['level']==l for p in practices) for l in ['senior1','senior2','senior3']},'uniqueQuestions':len({q['id'] for p in practices for q in p['unit']['questions']})}))
