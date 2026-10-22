#!/usr/bin/env python3
"""Export one-pass realtime scripts from SHA-bound authored listening manuscripts.

No synthesis, media copies, changes to frozen research or old audio assets.
The app chooses F1 on pass one and M5 on pass two at playback time.
"""
import hashlib,json,re
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'Research/GuYouJi-English-Benchmark'

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def ref(value):
 p=ROOT/value['path'] if value['path'].startswith(('build/','Backend/')) else BASE/value['path']
 assert digest(p)==value['sha256'], f'Changed frozen input: {p}'
 return p

def build():
 catalog=json.loads((ROOT/'Backend/config/learning/originals/catalog.json').read_text())
 page=(ROOT/'build/english-benchmark-quality-review/index.html').read_text()
 groups=json.loads(re.search(r'<script id="quality-data" type="application/json">(.*?)</script>',page,re.S)[1])['groups']
 included={u['unit']['originalGroup']['id'] for u in catalog['units']}
 cache=json.loads((ROOT/'Backend/config/learning/originals/media/conversion-cache.json').read_text())
 assets={}
 for gid,group in groups.items():
  if gid.lower() not in included or not group.get('requiredAudioAssets'):continue
  check=json.loads(ref(group['author_check']).read_text())
  generation=json.loads(ref(check['audio_generation']).read_text())
  manuscript=ref(generation['manuscript']);draft=json.loads(manuscript.read_text())
  cet='source_contract'in generation
  for index,asset in enumerate(group['requiredAudioAssets']):
   old=cache['audio:'+asset['asset']['sha256']]['id']
   clips=draft['clips'] if cet else [draft['clips'][index]]
   segments=[]
   def add(text,pause=350):
    if text and text.strip():segments.append(dict(text=text.strip(),pauseAfterMs=pause))
   if index==0 and draft.get('worked_example'):
    example=draft['worked_example'];q=example['question']
    add('Here is an example.',350)
    for turn in example['turns']:add(turn['text'])
    add(q['stem']+' '+' '.join(k+'. '+v for k,v in q['options'])+' The answer is '+q['answer']+'.',2000)
   # The published audio reference defines the response range. One authored
   # material pass replaces source-embedded repeats, which the app now manages.
   for clip in clips:
    if draft['family']=='listening_extract_choice':add(clip['context'],700)
    for turn in clip['turns']:
     if draft['family']=='listening_double_matching':add('Speaker '+turn['speaker'][1:]+'.',600)
     add(turn['text'])
    questions=[q.get('spoken_question',q.get('stem','')) for q in clip['questions']]
    spoken=[q for q in questions if '?'in q and not re.search(r'[\u3400-\u9fff]',q)]
    if spoken:
     segments[-1]['pauseAfterMs']=3000
     for question in spoken:add('Question: '+question,1500)
    if len(clips)>1:segments[-1]['pauseAfterMs']=2000
   assert segments
   assets[old]=dict(segments=segments,manuscript={'path':str(manuscript.relative_to(ROOT)),'sha256':digest(manuscript)},responseNumbers=asset['response_numbers'])
 assert set(assets)=={a['id']for a in catalog['audioAssets']}
 target=ROOT/'Backend/config/learning/listening-scripts.json'
 target.write_text(json.dumps(dict(version=1,playback='one-pass; F1 then M5 generated on device; no saved paired audio',assets=assets),ensure_ascii=False,indent=2)+'\n')
 print(json.dumps({'assets':len(assets),'segments':sum(len(a['segments']) for a in assets.values()),'bytes':target.stat().st_size}))
if __name__=='__main__':build()
