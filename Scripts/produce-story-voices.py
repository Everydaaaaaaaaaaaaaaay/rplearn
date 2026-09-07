#!/usr/bin/env python3
"""Screen local takes and publish prepared story resources. No remote AI calls.
Run screen --watch alongside the explicitly enabled Xcode production test;
master refuses any segment without an exact normalized ASR transcript.
"""
import argparse, hashlib, importlib.util, json, math, os, re, subprocess, time, unicodedata
from pathlib import Path
import numpy as np

spec=importlib.util.spec_from_file_location('master',Path(__file__).with_name('master-story-speech.py'))
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ROOT=Path(__file__).resolve().parent.parent

def canonical(text):
    # ASR may print digits rather than spoken number names. Normalize both without
    # discarding numeric content (Wharf 3 and Wharf 4 must remain different).
    from num2words import num2words
    text=text.lower().replace('’',"'")
    text=''.join(c for c in unicodedata.normalize('NFKD',text) if not unicodedata.combining(c))
    for short,full in {"should've":'should have',"could've":'could have',"would've":'would have','alright':'all right'}.items():
        text=re.sub(r'\b'+re.escape(short)+r'\b',full,text)
    text=re.sub(r'\b\d+\b', lambda n: num2words(int(n[0])),text)
    text=re.sub(r'\be\.?\s*m\.?\b',' e m ',text)
    lexical = re.findall(r"[a-z]+(?:'[a-z]+)?",text)
    # Orthographic variants and evidenced homophones are acoustically identical;
    # preserve the original transcript in the report instead of pretending these
    # spellings can be distinguished by listening. Never drop a word or number.
    variants = {'colours':'colors','colour':'color','neighbourhood':'neighborhood',
                'favourite':'favorite','realise':'realize','recognise':'recognize',
                'organised':'organized','catalogue':'catalog','theatre':'theater',
                'beets':'beats','sales':'sails','harbour':'harbor','neighbours':'neighbors',
                'programme':'program','favours':'favors','centre':'center',
                't':'tea','mei':'may','waits':'weights','too':'two',
                'aaliyah':'alia','leah':'lea','tahlia':'talia','talya':'talia',
                "chat's":'chats',"shop's":'shops',"tea's":'tease',
                'elena':'alaina'}
    return [variants.get(word,word) for word in lexical]

def dump(path,data):
    temporary=path.with_suffix('.tmp'); temporary.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n'); temporary.replace(path)

def model_for(name):
    if os.environ.get('STORY_VOICE_ASR') == 'mlx':
        return 'mlx-community/whisper-'+name+'-mlx'
    from faster_whisper import WhisperModel
    return WhisperModel(name,device='cpu',compute_type='int8',cpu_threads=3)

def recognize(model,path):
    if isinstance(model,str):
        import mlx_whisper
        return mlx_whisper.transcribe(str(path),path_or_hf_repo=model,language='en',
            condition_on_previous_text=False,temperature=0,verbose=None)['text'].strip()
    segments,_=model.transcribe(str(path),language='en',beam_size=5,condition_on_previous_text=False,vad_filter=False)
    return ' '.join(s.text.strip() for s in segments)

def screen(output,watch=False):
    base=model_for('base.en')
    cachepath=output/'screening.json'; cache=json.loads(cachepath.read_text()) if cachepath.exists() else {}
    while True:
        new=0
        for path in sorted(output.glob('candidate-*.json')):
            item=json.loads(path.read_text()); wav=output/item['file']
            if not wav.exists(): continue
            sha=hashlib.sha256(wav.read_bytes()).hexdigest()
            if item['file'] in cache and cache[item['file']]['sha256']==sha: continue
            audio=m.read_audio(wav); first,last,_=m.activity(audio)
            text=recognize(base,wav)
            row=dict(item,sha256=sha,recognized=text,wordEdits=m.edit_distance(canonical(item['text']),canonical(text)),
                activeSeconds=(last-first)/m.RATE,activeRMS=m.active_rms(audio),peak=float(np.max(np.abs(audio))),screenModel='base.en/'+os.environ.get('STORY_VOICE_ASR','faster-whisper'))
            cache[item['file']]=row; new+=1
            dump(cachepath,cache)
            if len(cache)%40==0: print(f'Screened {len(cache)} takes; exact {sum(r["wordEdits"]==0 for r in cache.values())}',flush=True)
        if not watch: break
        if (output/'render-complete').exists() and new==0: break
        time.sleep(4)

def select(output,plan):
    cachepath=output/'screening.json'; cache=json.loads(cachepath.read_text()); small=None
    for row in cache.values():
        row['wordEdits']=m.edit_distance(canonical(row['text']),canonical(row['recognized']))
    secondpath=output/'secondary-recognition.json'
    secondary=json.loads(secondpath.read_text()) if secondpath.exists() else {}
    selected={}; missing=[]
    for clip in plan['clips']:
        for segment in clip['segments']:
            rows=[r for r in cache.values() if r['segment']==segment['id'] and r['text']==segment['text'] and r['voice']==segment['voice']]
            # A final-clip review may have requested independent recognition of
            # all alternatives. Once available, use that evidence in selection.
            def accepted(r):
                transcript=secondary.get(r['sha256'])
                edits=m.edit_distance(canonical(r['text']),canonical(transcript)) if transcript is not None else r['wordEdits']
                return edits==0 and r['peak']<.95
            eligible=[r for r in rows if accepted(r)]
            if not eligible:
                # Independent recognizer resolves ASR-only rejects, never seed it
                # with the expected script. Preserve both transcripts in the review.
                if small is None: small=model_for('small.en')
                for row in rows:
                    if row['sha256'] not in secondary:
                        secondary[row['sha256']]=recognize(small,output/row['file'])
                        dump(secondpath,secondary)
                    row['secondTranscript']=secondary[row['sha256']]
                    row['secondEdits']=m.edit_distance(canonical(row['text']),canonical(row['secondTranscript']))
                    if row['secondEdits']==0 and row['peak']<.95: eligible.append(row)
            if not eligible:
                missing.append(dict(segment=segment['id'],expected=segment['text'],takes=[dict(take=r['take'],heard=r['recognized'],second=r.get('secondTranscript')) for r in rows]))
                continue
            center=float(np.median([r['activeSeconds'] for r in eligible])); level=float(np.median([r['activeRMS'] for r in eligible]))
            # Rare transient-heavy takes can force the whole collection several
            # dB quieter to preserve headroom. Prefer a clean alternative before
            # resorting to compression or flattening every line's dynamics.
            def score(r): return abs(math.log(r['activeSeconds']/center))+.03*abs(20*math.log10(r['activeRMS']/level))+2*max(0,math.log(max(r['peak'],1e-6)/.4))+(.035 if segment['breath'] and r['expression']=='none' else 0)
            selected[segment['id']]=min(eligible,key=lambda r:(score(r),r['take']))
    dump(output/'rejected-segments.json',missing)
    if missing: raise ValueError(f'{len(missing)} segments need review or additional takes; see rejected-segments.json')
    return selected

def master(output,destination):
    plan=json.loads((output/'production-plan.json').read_text()); selected=select(output,plan)
    parts={}; levels={}
    for clip in plan['clips']:
        for segment in clip['segments']:
            row=selected[segment['id']]
            part,_,_=m.trim_edges(m.read_audio(output/row['file']),row['expression']!='none')
            parts[segment['id']]=part
            levels.setdefault(clip['cast'],[]).append(m.active_rms(part))
    medians={k:float(np.median(v)) for k,v in levels.items()}; target=float(np.median(list(medians.values())))
    gains={k:max(-1.5,min(1.5,20*math.log10(target/v))) for k,v in medians.items()}
    # Measure the entire corpus once, then apply one constant gain globally.
    # Per-line loudness normalization would erase intentional dynamic differences.
    reference=np.concatenate([parts[s['id']]*10**(gains[c['cast']]/20) for c in plan['clips'] for s in c['segments']])
    m.write_audio(output/'corpus-unmastered.wav',reference)
    mastering=m.loudness_match(output/'corpus-unmastered.wav',output/'corpus-mastered.wav')
    manifest=dict(version=1,clips=[],silent=plan['silent']); review=[]
    destination.mkdir(parents=True,exist_ok=True)
    for clip in plan['clips']:
        clip_parts=[parts[s['id']]*10**((gains[clip['cast']]+mastering['gainDB'])/20) for s in clip['segments']]
        desired=[s['gapAfter'] for s in clip['segments']]
        # Interactive pages own their final beat. Count retained trailing silence
        # and the next clip's standard 100 ms lead, rather than stacking pauses.
        _,active_end,_=m.activity(clip_parts[-1])
        desired[-1]=max(0,desired[-1]-(len(clip_parts[-1])-active_end)/m.RATE-.1)
        audio,offsets,gaps=m.assemble(clip_parts,desired)
        filename='sv-'+clip['story']+'-'+clip['node']+'.m4a'; raw=output/'clip.wav'
        m.write_audio(raw,audio)
        subprocess.run(['ffmpeg','-v','error','-y','-i',str(raw),'-c:a','aac','-b:a','96k','-movflags','+faststart',str(destination/filename)],check=True)
        decoded=m.read_audio(destination/filename)
        if np.max(np.abs(decoded))>=.98: raise ValueError('Codec peak exceeds headroom: '+filename)
        row={k:clip[k] for k in ['story','node','sourceText','speaker','sourceSHA256']}
        row.update(voice=clip['segments'][0]['voice'],rate=clip['segments'][0]['rate'],file=filename,seconds=len(audio)/m.RATE,audioSHA256=hashlib.sha256((destination/filename).read_bytes()).hexdigest())
        manifest['clips'].append(row)
        review.append(dict(story=clip['story'],node=clip['node'],segments=[dict(id=s['id'],take=selected[s['id']]['take'],voice=selected[s['id']]['voice'],rate=selected[s['id']]['speed'],expression=selected[s['id']]['expression'],baseEdits=selected[s['id']]['wordEdits'],secondEdits=selected[s['id']].get('secondEdits'),intention=s['intention']) for s in clip['segments']],seconds=row['seconds'],gaps=gaps))
    raw.unlink(missing_ok=True)
    dump(destination/'story-voice-library.json',manifest)
    dump(output/'library-review.json',dict(roles=gains,mastering=mastering,clips=review))
    print(f'Published {len(review)} clips, {sum(c["seconds"] for c in review)/60:.2f} minutes',flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__); p.add_argument('action',choices=['screen','master']);p.add_argument('output',type=Path);p.add_argument('--watch',action='store_true');p.add_argument('--destination',type=Path,default=ROOT/'App/Resources/StoryVoices')
    a=p.parse_args(); screen(a.output,a.watch) if a.action=='screen' else master(a.output,a.destination)
