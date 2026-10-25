#!/usr/bin/env python3
"""Transform the already retained 2025 national-I paper into complete practices.
No network download; the protected source stays unchanged. Chart extracted with
pdftoppm from page 1; official question numbering is repost numbering + 20.
"""
import hashlib, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'build/english-benchmark-research-20261012'
OUT = ROOT/'Backend/config/learning/gaokao'
def digest(v):
    return hashlib.sha256(json.dumps(v,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def clean(t):
    return re.sub(r'第\s*\d+页/共\s*13页\n学科 网（北 京）股 份有限 公司\n','',t).strip()
pages=[clean(p['text']) for p in json.loads((SOURCE/'grade12-national2025-native-pages20261014.json').read_text())]
sha=hashlib.sha256((SOURCE/'raw/grade12-national2025-paper-commentary20261014.pdf').read_bytes()).hexdigest()
assert sha=='c20fe4a7d5227ede24a0519008501d5852c272de03c5bb4290cd7e5a035a531e'
text='\n'.join(pages[:8])
def span(start,end):return text.split(start,1)[1].split(end,1)[0].strip()
def flow(t):return re.sub(r'\s*\n\s*',' ',t).strip()
materials={
 'a':flow(span('\nA\n','\n1. ')),
 'b':flow(span('\nB\n','\n4. ')),
 'c':flow(span('\nC\n','\n8. ')),
 'd':flow(span('\nD\n','\n12. ')),
 'insertion':flow(span('An Unsung Hero','\nA. The cafe closes')),
 'cloze':flow(span('One August afternoon,','\n21. A. ')),
 'grammar':flow(span('An exhibition at the Jiushi Art Museum','\n第四部分')),
}
materials['insertion']='An Unsung Hero\n\n'+materials['insertion']
materials['cloze']='One August afternoon, '+materials['cloze']
materials['grammar']='An exhibition at the Jiushi Art Museum '+materials['grammar']
for k in ('insertion','cloze','grammar'):
 materials[k]=re.sub(r'_+(\d+)_+',lambda m:'____'+str(int(m[1])+20)+'____',materials[k])
# Preserve source paragraphs in the reader; line wraps are not paragraph boundaries.
for k in ('b','c','d'):
 raw=span('\n'+k.upper()+'\n','\n'+{'b':'4','c':'8','d':'12'}[k]+'. ')
 materials[k]=flow(raw)
# Restore printed paragraph boundaries after removing PDF line wraps.
paragraph_starts = {
 'a': ['The fuels for transport', 'PLANES —', 'CARS —', 'TRAINS —', 'TRUCKS —', 'SHIPS —', 'This energy transition'],
 'b': ['But things were different', 'As a new unit started', 'I walked into class'],
 'c': ['Dutch authors', 'Life on city streets', 'Although these campaigns', 'We invest a lot'],
 'd': ['Now, new research', 'Crucially, this process', 'Still, the findings', 'Scientists are still'],
 'insertion': ['Catherine Murphy,', 'Murphy gets up', 'One thing Murphy', '“I enjoy working'],
 'cloze': ['I took a picture', '____49____,', 'I sit in my apartment'],
 'grammar': ['“The exhibition', '“In a Go game', '“The players’ personalities', 'Tu says that'],
}
for name, starts in paragraph_starts.items():
 for start in starts:
  assert start in materials[name], (name, start)
  materials[name] = materials[name].replace(' '+start, '\n\n'+start, 1)
chart=(OUT/'2025-national1-transport-chart.png').read_bytes();chartsha=hashlib.sha256(chart).hexdigest();asset='image.'+chartsha
keys=list('CCBDDBACABACABD')+list('EDCFG')+list('CDACBBACDABCDAB')
assert len(keys)==35
expl=[
 '道路客运45.1%加道路货运29.4%，合计74.5%。',
 '火车一栏说明：有些已经电气化，其他也能以相对简单的方式改用电力。',
 '末段直接指出，需要加快可再生能源的发展。',
 '首段这些人物是学生创造的故事角色，不是真实的学生或家长。',
 '作者发现问题在于话题本身：学生并不认为单独讨论写作的重要性很有趣。',
 '后文写学生提交了长篇且打动人心的作品，说明结果令人惊喜。',
 '教师原本来教学生，最后也从学生的作品中认识到写作更深的意义。',
 '首段指出步行流动性下降，家长担心交通而开车接送。',
 '这些行动旨在保护社区、公园和城市的宜居性。',
 '下一段转折指出大多数西方城市仍围绕汽车需要重建，说明这些运动总体成效有限。',
 '全文反思道路只为快速通行服务的代价，Why the Rush?概括这一主旨。',
 '首段列举深海、高山、岩石、海鸟、南极雪及人体中的微塑料。',
 '第三段比较不同碳酸钙含量的水，说明硬度影响去除效果。',
 '瓶装水的例子说明微塑料暴露问题广泛且严重。',
 '末句建议升级饮用水处理厂，是将研究结果用于实践。',
 '首段引入咖啡馆，后文着重写微笑服务，E承上启下。',
 '下句顾客接过饮料，D中完成订单并喊出杯上姓名与之衔接。',
 '下句解释这样做是因为愿意为学生服务，C中提早到岗对应这个行为。',
 '此段介绍常客Wright，F中的her及为课堂做准备对应这位学生。',
 '下句表示她打算继续这份工作，G中17年的服务及不愿去别处工作与之对应。',
 '卖掉住房后要清空多年积累的物品，emptying out符合上下文。',
 '末段说明现在住在apartment，与此处新住处照应。',
 '租地方用于存放留下的重要物品，store符合语境。',
 '仍然塞满物品用be stuffed with。',
 '这些东西不特别值钱，但不应该被送进垃圾填埋场。',
 '网上出售花瓶，买家要求额外照片photos。',
 '搬家日期接近，与前文卖房及搬往城里照应。',
 '冒号后是发布物品的文字描述description。',
 '花瓶顺利送出使作者受到鼓励，于是继续发布。',
 '这些交换带来的上门拜访visits成为搬家忙乱中的亮光。',
 '让物品得到再利用可以减轻垃圾填埋场的负担，spare符合语境。',
 '交换让作者遇见原本可能不会遇到的人，encountered符合语境。',
 '新公寓里留下的是作者珍爱的物品belongings。',
 'take joy in表示从某事中获得快乐。',
 '旧物在别人那里得到珍惜和欣赏appreciating，呼应全文。',
]
groups={}
for name,lo,hi,family in [('a',1,3,'reading_choice'),('b',4,7,'reading_choice'),('c',8,11,'reading_choice'),('d',12,15,'reading_choice'),('insertion',16,20,'shared_insertion'),('cloze',21,35,'choice_cloze'),('grammar',36,45,'passage_form')]:
 qs=[]
 for n in range(lo,hi+1):
  q=dict(id=f'gk2025.n1.q{n+20}',goalId=f'gaokao.{family}',instruction='Read the complete passage and answer the question.',material=materials[name],hint='Return to the complete passage and check the surrounding context.',difficultyReason='2025年高考全国一卷原题；未做年级难度等值标定。')
  if name=='grammar':
   answers=['which','the','to present','guidance','are revealed','tries','by','strategic','and','digitally']
   ans=answers[n-36]
   q.update(type='completion',prompt=f'Complete gap {n+20}.',acceptedAnswers=[ans],normalization=dict(ignoreCase=True,ignoreTerminalPunctuation=False),marking=dict(protocol='gaokao_grammar_v1',rejectedAnswers=[],maxWords=2,unlisted='review'),explanation=f'参考答案：{ans}。结合本句结构和全文语义填写；未列形式进入复核，不凭相似度给分。')
  else:
   if name=='insertion':
    block=span('\nA. The cafe closes','\n第三部分');opts=re.split(r'\n([A-G])\. ', '\nA. The cafe closes '+block)
    options=[dict(id=opts[i].lower(),text=flow(opts[i+1])) for i in range(1,len(opts),2)]
    assert len(options)==7
    prompt=f'Choose the sentence for gap {n+20}.'
   else:
    prefix='\n'+str(n)+'. '
    block=text.split(prefix,1)[1]
    block=block.split('\n'+str(n+1)+'. ',1)[0] if n<hi else block.split('\n'+({'a':'B\n','b':'C\n','c':'D\n','d':'第二节','cloze':'第二节'}[name]),1)[0]
    if name=='cloze':prompt=f'Choose the best answer for gap {n+20}.'
    else:prompt=flow(block.split('A. ',1)[0])
    parts=re.split(r'(?:^|\s)([A-D])\. ',block)
    options=[dict(id=parts[i].lower(),text=flow(parts[i+1])) for i in range(1,len(parts),2)]
    assert len(options)==4,(n,options)
   q.update(type='choice',prompt=prompt,options=options,answer=keys[n-1].lower(),explanation=expl[n-1])
   if name=='a':q['materialImages']=[dict(assetId=asset,label='Global transport emissions in 2018 (original paper chart)')]
  qs.append(q)
 groups[name]=dict(id=f'gaokao.2025.national1.{name}',family=family,questionIds=[q['id'] for q in qs],sourceNumbers=list(range(lo+20,hi+21)),questions=qs)
source=dict(id='gaokao.2025.national1',year=2025,paper='2025年高考英语全国一卷',url='https://static-gkcx.gaokao.cn/upload/zhenti/20250611/1749605734_7546.pdf',sha256=sha,identityEvidenceURL='https://www.zjzs.net/art/2025/6/9/art_31_11269.html',numberingEvidenceURL='https://zy.21cnjy.com/24694444',numbering='本地转载卷笔试从1编号；与含听力完整卷逐组对照后，笔试题号加20，阅读21–35、七选五36–40、完形41–55、语法56–65。',scope='仅接入七个完整笔试闭集题组45题。原文、选项及参考键来自保留的试卷，图表保留；题型身份由浙江省教育考试院评析交叉核对。非官方答案认证；未接入听力和开放写作。')
practices=[]
for level in ('senior1','senior2','senior3'):
 for slug,names,label,minutes in [('reading-ab',['a','b'],'阅读理解 · 两篇',18),('reading-cd',['c','d'],'阅读理解 · 两篇',18),('cloze',['cloze'],'完形填空 · 一篇',15),('language',['insertion','grammar'],'七选五＋语法填空',16)]:
  gs=[groups[n] for n in names];qs=[q for g in gs for q in g['questions']];uid=f'gaokao.{level}.2025-national1.{slug}'
  # Per-question material is the component's complete source, never both readings flattened together.
  unit=dict(id=uid,version=1,schemaVersion=1,scoringVersion=1,roleKey='companion',roleVersion=1,level=level,title=f'2025全国一卷 · {label}',summary=f'{label}，共{len(qs)}题，建议约{minutes}分钟。',scene='按高考原题完整材料作答。',estimatedMinutes=minutes,goalIds=list(dict.fromkeys(q['goalId'] for q in qs)),prerequisiteGoalIds=[],references=[dict(sourceId=source['id'],unit=source['paper'],pages='转载PDF正文1–8页，参考答案11–12页',alignment='完整原题组；保留全文、选项、空位、图表和逐题参考答案。')],authorship=dict(kind='authored',author='高考原题数字化整理',reviewedBy='LingoTrip题源与完整性核读',reviewedAt='2026-10-23',reviewNotes='真题正文与参考键逐组核对；中文解析为本项目补充。未声称官方发布或学生实测等值。'),beats=[],questions=qs,originalGroup=dict(id=uid,family=gs[0]['family'] if len(gs)==1 or names==['a','b'] or names==['c','d'] else 'gaokao_language',label=label,candidateSHA256=sha,authorCheckSHA256=digest(qs),sourceGroupIds=[g['id'] for g in gs],sourceNotice=source['paper']+'真题；转载PDF题号已映射完整卷。',material=''))
  practices.append(dict(unit=unit,contentHash=digest(unit),components=[{k:v for k,v in g.items() if k!='questions'} for g in gs]))
OUT.mkdir(parents=True,exist_ok=True)
(OUT/'catalog.json').write_text(json.dumps(dict(version=1,source=source,practices=practices),ensure_ascii=False,indent=2)+'\n')
image=dict(id=asset,sha256=chartsha,byteSize=len(chart),width=630,height=228,contentType='image/png',description='高考原题交通排放占比图，2018年，六类运输方式及道路车辆合并边界完整。',source=source['url']+' PDF第1页原图区域，pdftoppm直接裁区渲染。',reviewedBy='LingoTrip题源与图表核读',reviewedAt='2026-10-23',reviewNotes='核对45.1、29.4、11.6、10.6、1、2.2及全部标签；未将四舍五入后的总和99.9改成100。')
(OUT/'image.json').write_text(json.dumps(image,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(dict(units=len(practices),uniqueQuestions=45,chartSHA256=chartsha),ensure_ascii=False))
