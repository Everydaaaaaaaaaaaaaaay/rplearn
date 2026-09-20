"""Operator-only import of reviewed example/translation pairs into the shared DB.
Uses the existing authenticated import API; idempotent checkpoint per batch.
Credentials are read only on the server and are never emitted.
"""
import json
import os
from pathlib import Path
import sys
import urllib.request
import generate_batch as generator

def publish(root):
    root=Path(root)
    jobs=json.loads((root/'jobs.json').read_text())
    token=Path(os.environ.get('EXAMPLE_ADMIN_TOKEN_FILE','/etc/lingotrip/admin-console-token')).read_text().strip()
    for path in sorted((root/'results').glob('*.json')):
        checkpoint=path.with_suffix('.imported')
        if checkpoint.exists():continue
        batch=json.loads(path.read_text());index=int(path.stem)
        generator.validate(batch,jobs[index*6:index*6+6])
        items=[]
        for item in batch['items']:
            for i,ex in enumerate(item['examples']):
                items.append(dict(lemma=item['lemma'],dictionary=dict(source='lingotrip-learner-examples',version='v1'),partOfSpeech=ex['pos'],senseDefinitionEn=ex['definition'],stableSenseId=f"{ex['pos']}-{-199+i}-{ex['definition']}",sentence=ex['sentence'],candidateMeaningsZhHans=[],sentenceZhHans=ex['sentenceZhHans'],contextualMeaningZhHans=ex['contextualMeaningZhHans'],promptVersion=batch['promptVersion'],translationModelVersion=batch['model']+'@2026-09-20-reviewed'))
        req=urllib.request.Request(os.environ.get('EXAMPLE_API_URL','http://127.0.0.1:8080')+'/internal/admin/dictionary/example-translations/import',data=json.dumps(dict(items=items)).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=60) as response:result=json.load(response)
        assert len(result['results'])==len(items) and all(x['status']=='ready' for x in result['results'])
        checkpoint.write_text(str(len(items)))
        print(f'imported {path.stem}: {len(items)} examples',flush=True)

if __name__=='__main__':publish(sys.argv[1])
