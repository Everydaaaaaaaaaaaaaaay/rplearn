#!/usr/bin/env python3
"""Lossless publication adapter for selected complete, objective authored groups.

Frozen author manuscripts stay unchanged. Unsupported response semantics hold the
whole group. Sources supply form rules; their text/keys are never exported.
"""
import argparse,base64,collections,hashlib,html,json,re,subprocess,tempfile,wave,struct,xml.etree.ElementTree as ET
from pathlib import Path
from html.parser import HTMLParser

ROOT=Path(__file__).resolve().parents[3]; BASE=ROOT/'Research/GuYouJi-English-Benchmark'
def sha(b):return hashlib.sha256(b).hexdigest()
def canonical(o):return json.dumps(o,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def ref(r):
 p=(ROOT/r['path']) if r['path'].startswith(('build/','Backend/')) else BASE/r['path']
 b=p.read_bytes()
 if sha(b)!=r['sha256']:raise ValueError('Changed frozen input: '+str(p))
 return p,b
class StudentHTML(HTMLParser):
 def __init__(self):super().__init__();self.text=[];self.images=[];self.skip=0
 def handle_starttag(self,t,a):
  a=dict(a)
  if t in ('script','style'):raise ValueError('Active material')
  if t=='audio':self.skip+=1
  if self.skip:return
  if t=='img':self.images.append((a['src'],a.get('alt','题目图形')))
  if t in ('p','h3','li','tr','br','figure'):self.text.append('\n')
  if t in ('td','th'):self.text.append(' | ')
  if t=='u':self.text.append('〔')
 def handle_endtag(self,t):
  if t=='audio':self.skip-=1;return
  if self.skip:return
  if t in ('p','h3','li','tr','figure'):self.text.append('\n')
  if t=='u':self.text.append('〕')
 def handle_data(self,d):
  if not self.skip:self.text.append(d)
 def value(self):return re.sub(r'\n[ \t]*\n+', '\n\n',''.join(self.text)).strip()

def run(args):
 page=(ROOT/args.page).read_text(); data=json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>',page,re.S)[1]); cells=data['common_type_view']['cells']
 out=ROOT/'Backend/config/learning/originals';media=out/'media';media.mkdir(parents=True,exist_ok=True)
 imgs={};audios={};entries=[];holds=[];conversions={};label_by_id={i:c for c in cells for i in c.get('groupIds',[])}
 cache_path=media/'conversion-cache.json';cache=json.loads(cache_path.read_text()) if cache_path.exists() else {}
 def audio(asset,check):
  source,raw=ref(asset['asset']);key='audio:'+sha(raw)
  if key in cache:
   meta=cache[key];audios[meta['id']]=meta;return dict(assetId=meta['id'],text=meta['transcript'],voice=meta['voice'])
  generation=json.loads(ref(check['audio_generation'])[1]);track=next((t for t in generation['tracks'] if t['sha256']==asset['asset']['sha256']),None)
  if not track or not track.get('segments'):raise ValueError('Audio transcript/track binding missing')
  transcript=' '.join(segment['text'] for segment in track['segments'] if segment.get('text'))
  with tempfile.TemporaryDirectory(prefix='original-audio-') as td:
   dst=Path(td)/'track.wav'
   subprocess.run(['ffmpeg','-v','error','-i',str(source),'-ar','24000','-ac','1','-c:a','pcm_s16le','-af','volume=0.92',str(dst)],check=True,capture_output=True)
   b=dst.read_bytes()
   with wave.open(str(dst)) as w:duration=round(w.getnframes()/24)
  digest=sha(b);id='audio.'+digest
  if duration>900000:raise ValueError('Complete track exceeds explicit 15-minute limit')
  target=media/(id+'.wav')
  if not target.exists():target.write_bytes(b)
  meta=dict(id=id,sha256=digest,byteSize=len(b),durationMs=duration,contentType='audio/wav',transcript=transcript,voice='research.local',reviewedAt='2026-10-19',reviewNotes='复用冻结原创音轨和逐段脚本，含原有复现次数与停顿；仅离线解码为24k单声道PCM并降低峰值。来源SHA '+asset['asset']['sha256']+'；未声称真人审听或自然听力标定。')
  audios[id]=meta;cache[key]=meta;cache_path.write_text(json.dumps(cache,ensure_ascii=False));return dict(assetId=id,text=transcript,voice='research.local')
 def image(src,label):
  if src in conversions:return conversions[src]
  if not src.startswith('data:image/svg+xml;base64,'):raise ValueError('Nonembedded image needs explicit binding')
  raw=base64.b64decode(src.split(',',1)[1]);
  tree=ET.fromstring(raw)
  for node in tree.iter():
   if node.tag.split('}')[-1] in ('script','image','foreignObject') or any(k.lower().startswith('on') or (k.split('}')[-1]=='href' and not v.startswith('#')) for k,v in node.attrib.items()):raise ValueError('Unsafe SVG')
  with tempfile.TemporaryDirectory(prefix='original-svg-') as td:
   inp=Path(td)/'input.svg';dst=Path(td)/'output.png';ET.register_namespace('', 'http://www.w3.org/2000/svg');inp.write_bytes(ET.tostring(tree,encoding='utf-8'))
   subprocess.run(['node',str(ROOT/'Scripts/render-original-svg.cjs'),args.sharp_module,str(inp),str(dst)],check=True,capture_output=True)
   b=dst.read_bytes()
  digest=sha(b);id='image.'+digest;width,height=struct.unpack('>II',b[16:24])
  if min(width,height)<128:raise ValueError('Image below production dimensions')
  target=media/(id+'.png')
  if not target.exists():target.write_bytes(b)
  imgs[id]=dict(id=id,sha256=digest,byteSize=len(b),width=width,height=height,contentType='image/png',description='原创题面图形；原标签：'+label,source='SHA-bound owned research SVG '+sha(raw),reviewedBy='Codex冻结作者稿接入检查',reviewedAt='2026-10-19',reviewNotes='复用原作者图意审核，离线SVG栅格化保留完整画布；未声称独立教师或学生验证。')
  conversions[src]=id;return id
 for gid,cell in label_by_id.items():
  g=data['groups'][gid]
  try:
   for field in ['candidate','author_check']:ref(g[field])
   if not g.get('anchor_group_ids'):raise ValueError('No source form binding')
   if g.get('wordEditing') or any(q.get('selectionSet') or q.get('fillPair') for q in g['questions']):raise ValueError('Coupled/word-edit response needs dedicated marking')
   check=json.loads(ref(g['author_check'])[1]);tracks={}
   for asset in g.get('requiredAudioAssets',[]):
    recording=audio(asset,check)
    for n in asset['response_numbers']:
     if n in tracks:raise ValueError('Response requires multiple independent tracks')
     tracks[n]=recording
   if tracks and set(tracks)!=set(q['number'] for q in g['questions']):raise ValueError('Audio response coverage incomplete')
   parser=StudentHTML();parser.feed((g.get('studentBeforeHtml') or '')+g['passageHtml']+(g.get('studentAfterHtml') or ''));material=parser.value()
   if len(material)>24000:raise ValueError('Material exceeds explicit limit')
   pictures=[dict(assetId=image(src,label),label=label) for src,label in parser.images]
   if g.get('requiredPassageImages') and len(pictures)!=len(g['requiredPassageImages']):raise ValueError('Missing positioned image')
   questions=[]
   for q in g['questions']:
    prompt=q['stem']; options=q.get('options') or []
    if q.get('stemHtml'):
     stem=StudentHTML();stem.feed(q['stemHtml']);prompt=stem.value()
    common=dict(id='q'+str(q['number']),goalId='original.'+cell['family'],instruction=g.get('instruction') or cell['label'],prompt=prompt,explanation=q['rationale'],hint='请结合完整材料与题目要求作答。',difficultyReason='按已核源题完整形式创作；未声称全国年级等值。')
    if pictures:
     per_response = cell['family']=='listening_picture_true_false' and len(pictures)==len(g['questions']) and all(p['label']=='第'+str(item['number'])+'图' for p,item in zip(pictures,g['questions']))
     common['materialImages']=[pictures[g['questions'].index(q)]] if per_response else pictures
    if options:
     if len(options)>20 or str(q.get('answer')) not in [str(a) for a,b in options]:raise ValueError('Non-single selection')
     opts=[]
     for a,b in options:
      row=dict(id='o'+str(len(opts)),text=(str(a)+'. '+str(b)).strip())
      if q.get('optionImages'):
       im=q['optionImages'][a];ref(im['asset']);row['imageAssetId']=image(im['src'],im['alt'])
      opts.append(row)
     questions.append(dict(**common,**({'type':'listeningChoice','audio':tracks[q['number']]} if tracks else {'type':'choice'}),options=opts,answer='o'+str([str(a) for a,b in options].index(str(q['answer'])))))
    else:
     fm=q.get('fillMarking'); answers=q.get('acceptedAnswers')
     if not fm or not answers or fm['normalization'] not in ['english_phrase_v1','source_excerpt_v1','latin_word_v1','small_count_v1','clock_hour_v1','whole_sentence_tokens_v1']:raise ValueError('Unsupported fill normalization or nonobjective response')
     if fm.get('initial') or q.get('prefix') or q.get('suffix'):raise ValueError('Partial-word constraint needs dedicated adapter')
     questions.append(dict(**common,type='completion',acceptedAnswers=answers,normalization=dict(ignoreCase=fm['normalization']!='whole_sentence_tokens_v1',ignoreTerminalPunctuation=False),**({'audio':tracks[q['number']]} if tracks else {}),marking=dict(**{k:fm[k] for k in ['minWords','requiredInitial','requiredWord'] if k in fm},protocol=fm['normalization'],rejectedAnswers=fm.get('rejectedAnswers',[]),maxWords=fm.get('maxWords'),unlisted='review')))
   if not 2<=len(questions)<=40:raise ValueError('Whole response count outside contract')
   level=g['grade'];level='junior'+str(level-6) if isinstance(level,int) and level<10 else 'senior'+str(level-9) if isinstance(level,int) else level
   title=g.get('title') or (cell['label']+' · '+gid)
   title=title[:100]
   unit=dict(id='original.'+gid.lower(),version=1,schemaVersion=1,scoringVersion=1,roleKey='companion',roleVersion=1,level=level,title=title,summary=cell['label'],scene='完整原创练习。阅读全部材料，按题面要求依次作答；答案由服务端判定。',estimatedMinutes=max(2,min(20,len(questions)*2)),goalIds=['original.'+cell['family']],prerequisiteGoalIds=[],references=[dict(sourceId='research.exam-forms',unit='；'.join(g['anchor_group_ids'])[:200],pages='冻结来源组选节；以源绑定记录为准',alignment=(g.get('sourceFormNotice') or '源题只用于完整题型规则，正文和答案为原创。')[:500])],authorship=dict(kind='authored',author='冻结研究作者稿',reviewedBy='Codex复用作者逐题审核并核接入',reviewedAt='2026-10-19',reviewNotes='无损映射既有原创完整输入与逐题依据，不把模型自审升级为独立教研或学生验证。'),beats=[],questions=questions,originalGroup=dict(id=gid.lower(),family=cell['family'],label=cell['label'],candidateSHA256=g['candidate']['sha256'],authorCheckSHA256=g['author_check']['sha256'],sourceGroupIds=g['anchor_group_ids'],sourceNotice=g.get('sourceFormNotice',''),material=material))
   student=dict(material=material,questions=[dict(id=q['id'],type=q['type'],prompt=q['prompt'],instruction=q['instruction'],options=q.get('options'),audio=q.get('audio',{}).get('assetId'),images=q.get('materialImages',[])) for q in questions])
   probes=[]
   for q in questions:
    if q['type'] in ['choice','listeningChoice']:
     probes += [dict(questionId=q['id'],answer=dict(kind='choice',optionId=o['id']),outcome='correct' if o['id']==q['answer'] else 'incorrect') for o in q['options']]
    else:
     probes += [dict(questionId=q['id'],answer=dict(kind='text',text=a),outcome='correct') for a in q['acceptedAnswers']]
     probes += [dict(questionId=q['id'],answer=dict(kind='text',text=a),outcome='incorrect') for a in q['marking']['rejectedAnswers'] or ['']]
   entries.append(dict(unit=unit,contentHash=sha(canonical(unit).encode()),authoredPayloadSHA256=sha(canonical(g).encode()),studentInputHash=sha(canonical(student).encode()),probes=probes))
  except (ValueError,KeyError,subprocess.CalledProcessError,ET.ParseError) as e:holds.append(dict(id=gid,level=str(g['grade']),family=cell['family'],reason=(e.stderr.decode()[:500] if isinstance(e,subprocess.CalledProcessError) else str(e))))
 # Export only used media; do not upload orphan render attempts from held groups.
 used={m['assetId'] for e in entries for q in e['unit']['questions'] for m in q.get('materialImages',[])}|{o['imageAssetId'] for e in entries for q in e['unit']['questions'] for o in q.get('options',[]) if 'imageAssetId'in o}
 manifest=dict(version=1,researchPlanSHA256=sha((BASE/data['active_run_plan']).read_bytes()),scopeSHA256=data['common_type_view']['scope_ref']['sha256'],reviewBoundary='来源用于题型与判分规则；发布的是既有原创完整稿。沿用作者审核，独立教师、学生难度和商业效度未证。',units=entries,audioAssets=[v for k,v in audios.items() if any(q.get('audio',{}).get('assetId')==k for e in entries for q in e['unit']['questions'])],imageAssets=[v for k,v in imgs.items() if k in used])
 batches=[]; pending=[]; weight=0; media_sizes={a['id']:a['byteSize'] for a in manifest['audioAssets']+manifest['imageAssets']}
 for entry in entries:
  ids={q['audio']['assetId'] for q in entry['unit']['questions'] if q.get('audio')}|{im['assetId'] for q in entry['unit']['questions'] for im in q.get('materialImages',[])}|{o['imageAssetId'] for q in entry['unit']['questions'] for o in q.get('options',[]) if 'imageAssetId' in o}
  size=sum(media_sizes[i] for i in ids)
  if pending and (weight+size>64000000 or len(pending)>=20):
   batches.append(dict(id='b'+str(len(batches)).zfill(3),unitIds=pending));pending=[];weight=0
  pending.append(entry['unit']['id']);weight+=size
 if pending:batches.append(dict(id='b'+str(len(batches)).zfill(3),unitIds=pending))
 manifest['batches']=batches
 (out/'catalog.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
 report=dict(researchGroups=len(data['groups']),inScopeGroups=len(label_by_id),exportedGroups=len(entries),exportedResponses=sum(len(e['unit']['questions']) for e in entries),levels=dict(collections.Counter(e['unit']['level'] for e in entries)),held=holds,imageObjects=len(used),audioObjects=len(manifest['audioAssets']),notNewlyAuthored=True)
 (ROOT/'build/learning-originals-export.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='held'},ensure_ascii=False))
if __name__=='__main__':
 a=argparse.ArgumentParser();a.add_argument('--page',default='build/english-benchmark-quality-review/index.html');a.add_argument('--sharp-module',required=True);run(a.parse_args())
