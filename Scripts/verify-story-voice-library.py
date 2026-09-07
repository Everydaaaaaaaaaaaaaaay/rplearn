#!/usr/bin/env python3
"""Verify shipped compressed audio against every eligible source node.
--recognize additionally checks final, decoded clips with independent small.en ASR.
"""
import argparse, hashlib, importlib.util, json
from pathlib import Path
import numpy as np

def module(name,file):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(file));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
production=module('production','produce-story-voices.py'); planner=module('planner','plan-story-voices.py')

def verify(destination,output,recognition=False):
    manifest=json.loads((destination/'story-voice-library.json').read_text());plan=planner.build()
    expected={(c['story'],c['node']):c for c in plan['clips']}
    actual={(c['story'],c['node']):c for c in manifest['clips']}
    assert len(actual)==len(manifest['clips']) and actual.keys()==expected.keys(),'Coverage mismatch'
    assert manifest['silent']==plan['silent'],'Silent coverage mismatch'
    files={c['file'] for c in actual.values()};assert len(files)==len(actual),'Duplicate clip file'
    assert files=={p.name for p in destination.glob('sv-*.m4a')},'Orphaned assets'
    output.mkdir(parents=True,exist_ok=True);cachepath=output/'final-recognition.json'
    cache=json.loads(cachepath.read_text()) if cachepath.exists() else {}
    if recognition:
        model=production.model_for('small.en')
    rows=[]
    for key,row in actual.items():
        original=expected[key]
        for field in ['sourceText','speaker','sourceSHA256']:assert row[field]==original[field],(key,field)
        path=destination/row['file'];digest=hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest==row['audioSHA256'],key
        audio=production.m.read_audio(path)
        peak=float(np.max(np.abs(audio)));seconds=len(audio)/production.m.RATE
        assert peak<.98 and abs(seconds-row['seconds'])<.1,(key,'codec integrity')
        review=dict(story=key[0],node=key[1],seconds=seconds,peak=peak)
        if recognition:
            if digest not in cache:
                text=production.recognize(model,path)
                cache[digest]=text;production.dump(cachepath,cache)
            text=cache[digest]
            review.update(expected=row['sourceText'],recognized=text,wordEdits=production.m.edit_distance(production.canonical(row['sourceText']),production.canonical(text)))
        rows.append(review)
        if len(rows)%20==0:print(f'Verified {len(rows)}/{len(actual)} final clips',flush=True)
    report=dict(stories=len({c['story'] for c in rows}),clips=len(rows),seconds=sum(c['seconds'] for c in rows),bytes=sum((destination/f).stat().st_size for f in files),model='small.en' if recognition else None,rows=rows)
    if recognition:report['transcriptDisagreements']=[r for r in rows if r['wordEdits']]
    production.dump(output/'final-library-check.json',report)
    print(json.dumps({k:v for k,v in report.items() if k not in ['rows','transcriptDisagreements']},ensure_ascii=False),flush=True)
    if recognition and report['transcriptDisagreements']:
        print(f"REVIEW REQUIRED: {len(report['transcriptDisagreements'])} final ASR disagreements (not automatically synthesis errors)",flush=True)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('destination',type=Path);p.add_argument('output',type=Path);p.add_argument('--recognize',action='store_true');a=p.parse_args();verify(a.destination,a.output,a.recognize)
