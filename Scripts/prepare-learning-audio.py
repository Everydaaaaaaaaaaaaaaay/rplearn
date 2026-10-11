#!/usr/bin/env python3
"""为已审定完整台词制作本地音频证据，不编写或改写题目。"""
import json,re,subprocess,wave,hashlib,sys,itertools
from pathlib import Path
import numpy as np
from faster_whisper import WhisperModel

if len(sys.argv) < 2:
    raise SystemExit('用法：prepare-learning-audio.py build内录音目录 [candidates|assemble|masters]')
repo_root=Path(__file__).resolve().parent.parent
root=Path(sys.argv[1]).resolve()
assert root.is_relative_to(repo_root / 'build'), '仅允许本仓库build内音频'
cache=repo_root / 'build/learning-audio-20260926/models'
contractions={"i'm":"i am","it's":"it is","we're":"we are","didn't":"did not","we've":"we have","isn't":"is not","don't":"do not","i'll":"i will","i'd":"i would","where's":"where is","they're":"they are"}
numbers={"1":"one","2":"two","3":"three","7":"seven","12":"twelve","4":"four","5":"five","6":"six","8":"eight","9":"nine","10":"ten","40":"forty"}
# 只处理明确英美拼写和不可听辨的所有格撇号；保留末尾s，不容许漏词或改变时态。
# 两个名词的原始ASR文本仍保存，避免为了标点差异反复生产完全相同的录音。
orthography={"practise":"practice", "recognise":"recognize", "week's":"weeks", "engineer's":"engineers"}
def norm(s):
    # ASR货币书写展开，不删除金额或币种；原始识别原文仍保留。
    s=re.sub(r"\$(\d+)",r"\1 dollars",s)
    s=re.sub(r"\b1st\b", "first", s, flags=re.I)
    words=re.findall(r"[a-zé]+(?:'[a-zé]+)?|[0-9]+",s.lower().replace('’',"'"))
    return [t for w in words for t in contractions.get(w,numbers.get(w,orthography.get(w,w))).split()]
def stats(path):
    with wave.open(str(path)) as w:
        assert (w.getframerate(),w.getnchannels(),w.getsampwidth())==(24000,1,2)
        x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float64)
    active=np.flatnonzero(np.abs(x)>128); assert len(active)
    return {'sampleRate':24000,'channels':1,'sampleWidth':2,'durationSeconds':len(x)/24000,'durationMs':round(len(x)/24),'peak':int(np.abs(x).max()),'rms':float(np.sqrt(np.mean(x*x))),'clippedSamples':int((np.abs(x)>=32767).sum()),'leadingSilenceSeconds':float(active[0]/24000),'trailingSilenceSeconds':float((len(x)-1-active[-1])/24000),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'byteSize':path.stat().st_size}
def save(name,data):
    (root/name).write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
def recognize(rows,pathkey,field,outname):
    for name in ['base.en','small.en']:
        model=WhisperModel(name,device='cpu',compute_type='int8',cpu_threads=2,download_root=str(cache),local_files_only=True)
        for row in rows:
            if name in row.get(field,{}):
                row[field][name]['exact']=norm(row[field][name]['text'])==norm(row['text'])
                row[field][name]['tokens']=norm(row[field][name]['text'])
                continue
            segments,_=model.transcribe(str(root/row[pathkey]),language='en',beam_size=5,condition_on_previous_text=False,vad_filter=False)
            actual=' '.join(s.text.strip() for s in segments)
            row.setdefault(field,{})[name]={'text':actual,'exact':norm(actual)==norm(row['text']),'tokens':norm(actual)}
            print(row.get('segment',row.get('questionId')),row.get('take'),name,round(row['wpm'],1),actual,norm(actual)==norm(row['text']),flush=True)
            save(outname,rows)
        del model
mode=sys.argv[2] if len(sys.argv)>2 else 'candidates'
assert mode in {'candidates','assemble','masters'}, '模式必须为candidates、assemble或masters'
if mode=='candidates':
    rows=[]
    prior={r['pcmFile']:r for r in json.loads((root/'recognition.json').read_text())} if (root/'recognition.json').exists() else {}
    for f in sorted(root.glob('candidate-*.json')):
        row=json.loads(f.read_text()); out=root/(f.stem+'.pcm.wav')
        source_digest=hashlib.sha256((root/row['file']).read_bytes()).hexdigest()
        if not out.exists() or prior.get(out.name,{}).get('sourceSha256')!=source_digest:
            subprocess.run(['ffmpeg','-v','error','-y','-i',str(root/row['file']),'-ar','24000','-ac','1','-c:a','pcm_s16le',str(out)],check=True)
        row['sourceSha256']=source_digest; row['pcmFile']=out.name; row.update(stats(out)); row['wpm']=len(row['text'].split())/row['durationSeconds']*60
        old=prior.get(out.name,{})
        if old.get('sha256')==row['sha256']: row['recognition']=old.get('recognition',{})
        rows.append(row)
    recognize(rows,'pcmFile','recognition','recognition.json'); save('recognition.json',rows)
elif mode=='assemble':
    rows=json.loads((root/'recognition.json').read_text()); plan=json.loads((root/'production-plan.json').read_text()); selection=[]; missing=[]; manifest=[]
    rejected=json.loads((root/'master-rejections.json').read_text()) if (root/'master-rejections.json').exists() else []
    for clip in plan['clips']:
        spoken=' '.join(seg['text'] for seg in clip['segments'])
        candidates=[]
        for seg in clip['segments']:
            candidates.append([r for r in rows if r['segment']==seg['id'] and r['text']==seg['text'] and r['voice']==seg['voice'] and r['speaker']==seg['speaker'] and all(r.get('recognition',{}).get(m,{}).get('exact') for m in ['base.en','small.en']) and r['clippedSamples']==0 and r['durationSeconds']<60 and r['leadingSilenceSeconds']<0.7 and r['trailingSilenceSeconds']<0.9])
        combos=[]
        for combo in itertools.product(*candidates):
            signature=[r['pcmFile'] for r in combo]
            if any(x['questionId']==clip['questionId'] and x['segments']==signature for x in rejected): continue
            duration=sum(r['durationSeconds'] for r in combo)+.3*(len(combo)-1)
            wpm=len(spoken.split())/duration*60
            if clip['minimumWpm']<=wpm<=clip['maximumWpm']: combos.append((abs(wpm-clip['targetWpm']),combo))
        if not combos:
            missing.append(clip['id']); print('待补录',clip['id'],flush=True); continue
        combo=min(combos,key=lambda x:x[0])[1]; pieces=[]; segments=[]; offset=0; gaps=[]
        for i,r in enumerate(combo):
            with wave.open(str(root/r['pcmFile'])) as w: x=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float64)
            pieces.append(x)
            segments.append({'speaker':r['speaker'],'voice':r['voice'],'text':r['text'],'take':r['take'],'speed':r['speed'],'steps':r['steps'],'expression':r['expression'],'sourcePath':str(root/r['pcmFile']),'sha256':r['sha256'],'startSample':offset,'endSampleExclusive':offset+len(x),'candidateRecognition':r['recognition']})
            offset+=len(x)
            if i<len(combo)-1:
                gaps.append({'startSample':offset,'endSampleExclusive':offset+7200}); pieces.append(np.zeros(7200)); offset+=7200
        x=np.concatenate(pieces); rms=float(np.sqrt(np.mean(x*x))); peak=float(np.abs(x).max()); gain=min(3000/rms,27000/peak); y=np.rint(x*gain).astype('<i2'); out=root/(clip['id']+'.wav')
        with wave.open(str(out),'wb') as w: w.setnchannels(1); w.setsampwidth(2); w.setframerate(24000); w.writeframes(y.tobytes())
        assert all(np.all(y[g['startSample']:g['endSampleExclusive']]==0) for g in gaps)
        s=stats(out); speakers=list({r['speaker']:{'id':r['speaker'],'voice':r['voice']} for r in combo}.values())
        row={'questionId':clip['questionId'],'segment':clip['id'],'text':spoken,'transcript':clip['transcript'],'masterFile':out.name,'masterPath':str(out),'gain':gain,'masterStats':s,'wpm':len(spoken.split())/s['durationSeconds']*60,'segments':list(combo),'speakers':speakers,'voice':'+'.join(dict.fromkeys(r['voice'] for r in combo)),'interSegmentSilenceMs':300 if len(combo)>1 else 0}
        old=next((x for x in json.loads((root/'selection.json').read_text()) if x['questionId']==row['questionId']),{}) if (root/'selection.json').exists() else {}
        if old.get('masterStats',{}).get('sha256')==s['sha256']: row['masterRecognition']=old.get('masterRecognition',{})
        selection.append(row)
        manifest.append({'questionId':clip['questionId'],'masterPath':str(out),'masterSha256':s['sha256'],'transcript':clip['transcript'],'segments':segments,'gain':gain,'insertedGapSamples':7200 if gaps else 0,'gaps':gaps,'sampleRate':24000,'note':'仅重采样、整段增益和对话间300毫秒数字静音；没有后处理变速、删词或逐词拼接。'})
    save('selection.json',selection); save('missing.json',missing); save('manifest.json',manifest)
elif mode=='masters':
    rows=json.loads((root/'selection.json').read_text()); recognize(rows,'masterFile','masterRecognition','selection.json'); save('selection.json',rows)
    for row in rows: print('母版',row['questionId'],all(row['masterRecognition'][m]['exact'] for m in ['base.en','small.en']),flush=True)
