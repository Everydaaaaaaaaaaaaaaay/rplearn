"""Audit the full top-5000 seed; optionally check real shared-cache hits without generation."""
import argparse
import collections
import concurrent.futures
import hashlib
import json
from pathlib import Path
import sqlite3
import urllib.request
import unicodedata
import batch
import generate_batch

ROOT=Path(__file__).resolve().parent

def audit():
    jobs=json.loads((ROOT/'top5000-jobs.v1.json').read_text())
    records=[json.loads(line) for line in (ROOT/'top5000.v1.jsonl').read_text().splitlines()]
    expected={}
    assert len(records)==(len(jobs)+5)//6
    for i,record in enumerate(records):
        required=jobs[i*6:i*6+6]
        assert record['fingerprint']==hashlib.sha256(json.dumps(required,sort_keys=True).encode()).hexdigest()
        generate_batch.validate(record,required)
        for item in record['items']:
            for ex in item['examples']:
                key=(item['lemma'],ex['sentence'])
                assert key not in expected
                expected[key]=ex
    db=sqlite3.connect(f'file:{batch.ROOT}/App/Resources/learner_dictionary.sqlite?mode=ro',uri=True);db.row_factory=sqlite3.Row
    selected=list(batch.seed.iter_jobs(db));counts=collections.Counter(x['lemma'] for x in selected)
    words=list(batch.seed.iter_top_words(db))
    assert len(words)==5000
    assert all(2<=counts[w['wl']]<=4 for w in words)
    supplemented=[j for j in selected if j['senseRank'] < -100]
    assert len(supplemented)==len(expected)==3757
    assert set((j['lemma'],j['sentence']) for j in supplemented)==set(expected)
    assert db.execute('pragma integrity_check').fetchone()[0]=='ok'
    print(json.dumps(dict(words=5000,displayedExamples=len(selected),addedExamples=len(expected),distribution=dict(collections.Counter(counts.values())))))
    return supplemented,expected

def online(base,jobs,expected):
    def check(part):
        requests=[dict(requestId=str(i),lemma=j['lemma'],dictionary=dict(source=j['dictionarySource'],version=j['dictionaryVersion']),partOfSpeech=j['partOfSpeech'],senseDefinitionEn=j['senseDefinition'],stableSenseId=j['stableSenseId'],sentence=j['sentence'],candidateMeaningsZhHans=j['candidateMeaningsZhHans']) for i,j in enumerate(part)]
        req=urllib.request.Request(base+'/v1/dictionary/example-translations/resolve',data=json.dumps(dict(generateOnMiss=False,requests=requests)).encode(),headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=60) as response:data=json.load(response)
        assert len(data['results'])==len(part)
        indexed={x['requestId']:x for x in data['results']}
        for i,j in enumerate(part):
            result=indexed[str(i)];ex=expected[(j['lemma'],j['sentence'])]
            assert result['status']=='ready',(j['lemma'],j['sentence'],result['status'])
            assert result['sentenceZhHans']==unicodedata.normalize('NFKC',ex['sentenceZhHans']).strip(), (j['lemma'], j['sentence'], result['sentenceZhHans'], ex['sentenceZhHans'])
            assert result['contextualMeaningZhHans']==unicodedata.normalize('NFKC',ex['contextualMeaningZhHans']).strip(), (j['lemma'], result['contextualMeaningZhHans'], ex['contextualMeaningZhHans'])
        return len(part)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        total=sum(pool.map(check,[jobs[i:i+32] for i in range(0,len(jobs),32)]))
    print('Verified real shared translation cache hits:',total,'; generateOnMiss=false for every request')
    words=list(dict.fromkeys(j['lemma'] for j in jobs))
    for lemma in words[::100]+["n't",words[-1]]:
        with urllib.request.urlopen(base+'/v1/dictionary/learner-examples/'+urllib.parse.quote(lemma,safe=''),timeout=30) as response:data=json.load(response)
        wanted=[ex for (w,_),ex in expected.items() if w==lemma]
        assert {(x['sentence'],x['sentenceZhHans']) for x in data['examples']}=={(unicodedata.normalize('NFKC',x['sentence']),unicodedata.normalize('NFKC',x['sentenceZhHans'])) for x in wanted},lemma
    print('Verified live catalog samples:',len(words[::100])+2)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--live-base');args=p.parse_args()
    jobs,expected=audit()
    if args.live_base:online(args.live_base.rstrip('/'),jobs,expected)
