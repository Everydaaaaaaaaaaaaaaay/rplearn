#!/usr/bin/env python3
"""Build a word-preserving production plan from all shipped playable scripts.
Direction and casting are authored in data/story-voice-directions.json.
"""
import argparse, hashlib, json, re, unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def words(text):
    return re.findall(r"[a-z0-9]+(?:'[a-z]+)?", text.lower().replace('’', "'"))

def split(text, breath=False):
    # Keep punctuation as performance information; remove decorative quotation marks.
    text = text.replace('『', '').replace('』', '').strip()
    remaining = text.split(); result = []
    while remaining:
        cap = 61 if breath and not result else 70
        fit = 0
        for i in range(1, len(remaining)+1):
            if len(unicodedata.normalize('NFKD', ' '.join(remaining[:i]))) > cap: break
            fit = i
        if not fit: raise ValueError('A token exceeds the renderer cap')
        # Prefer a complete sentence/clause, but avoid creating an orphan one-word tail.
        if fit < len(remaining):
            boundaries = [i for i in range(3, fit+1) if re.search(r'[.!?,;:—][\"\x27]?$' , remaining[i-1])]
            if boundaries: fit = boundaries[-1]
            elif len(remaining)-fit < 3: fit = max(1, fit-2)
        result.append(' '.join(remaining[:fit])); remaining = remaining[fit:]
    assert words(' '.join(result)) == words(text)
    return result

def build():
    directions = json.loads((ROOT/'Scripts/data/story-voice-directions.json').read_text())
    clips=[]; silent=[]
    paths=sorted((ROOT/'App/Resources/Stories').glob('*.json'))
    for path in paths:
        if not path.stem.startswith('departures_'): continue
        story=json.loads(path.read_text())
        if 'nodes' not in story: continue
        story_id=story['id']
        for node in story['nodes']:
            text=node['text']; speaker=node['speaker']; key=path.stem+'/'+node['id']
            if speaker in ['你','你的选择'] or node.get('choices') or re.search(r'[\u3400-\u9fff]',text):
                silent.append(dict(story=story_id,node=node['id'],reason='player/choice' if speaker in ['你','你的选择'] or node.get('choices') else 'unsupported-Chinese'))
                continue
            role=speaker if speaker in directions['cast'] else path.stem+'/'+speaker
            cast=directions['cast'][role]
            cue=dict(directions['scenes'].get(path.stem,dict(intention='自然场景对话',gapAfter=.35)))
            if node.get('speech'):
                authored=node['speech'];cue.update(rate=authored['speed'],gapAfter=authored['after'],intention=authored['intention'],breath=authored.get('expression')=='breath')
            cue.update(directions['overrides'].get(key,{}))
            rate=cue.get('rate',cast['rate'])
            pause=(node.get('speech') or {}).get('pauseAfter')
            if pause and text.startswith(pause) and len(pause)<len(text):
                chunks=split(pause,cue.get('breath',False))+split(text[len(pause):].strip())
            else: chunks=split(text,cue.get('breath',False))
            segments=[]
            for i,chunk in enumerate(chunks):
                gap=cue['gapAfter'] if i==len(chunks)-1 else (node.get('speech') or {}).get('pauseDuration',.26) if re.search(r'[.!?][\"\x27]?$',chunk) else .13
                segments.append(dict(id=f"{path.stem}-{node['id']}-{i}",text=chunk,speaker=role,voice=cast['voice'],rate=rate,
                                     gapAfter=gap,breath=cue.get('breath',False) and i==0,intention=cue['intention']))
            clips.append(dict(story=story_id,node=node['id'],sourceText=text,speaker=speaker,cast=role,
                sourceSHA256=hashlib.sha256((speaker+'\n'+text).encode()).hexdigest(),segments=segments))
    return dict(version=1,candidatesPerSegment=4,clips=clips,silent=silent)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__); parser.add_argument('output',type=Path)
    args=parser.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    plan=build(); (args.output/'production-plan.json').write_text(json.dumps(plan,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(dict(stories=len({c['story'] for c in plan['clips']}),clips=len(plan['clips']),segments=sum(len(c['segments']) for c in plan['clips']),silent=len(plan['silent']))))
