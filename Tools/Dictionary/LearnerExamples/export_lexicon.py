"""Export the authoritative bundled lexical baseline for server generation eligibility.
No user data; never trusts a client's claimed word, definition or example count.
"""
import gzip
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import sys
import batch

source=batch.ROOT/'App/Resources/learner_dictionary.sqlite'
version=hashlib.sha256(source.read_bytes()).hexdigest()
db=sqlite3.connect(f'file:{source}?mode=ro',uri=True);db.row_factory=sqlite3.Row
output=Path(sys.argv[1]);count=0
with output.open('wb') as raw, gzip.GzipFile(filename='',mode='wb',fileobj=raw,mtime=0) as zipped:
    for word in db.execute('select wl,translation,definition,exchange,bnc,frq,0 as seed_rank,0 as effective_rank from word order by wl'):
        lemma=word['wl'].lower().strip()
        if not re.fullmatch(r"[a-z][a-z' -]{0,119}",lemma) or not (word['translation'] or word['definition']): continue
        examples=list(batch.seed.iter_jobs(db,[word]))[:2]
        forms=[p.split(':',1)[1] for p in (word['exchange'] or '').split('/') if ':' in p and p.split(':',1)[0] in {'0','p','d','i','3','s','r','t'}]
        record=dict(lemma=lemma,definition=(word['definition'] or '')[:800],meaning=(word['translation'] or '')[:800],forms=forms,existingExamples=[e['sentence'] for e in examples],sourceVersion=version)
        zipped.write((json.dumps(record,ensure_ascii=False,separators=(',',':'))+'\n').encode())
        count+=1
print(json.dumps(dict(entries=count,sourceVersion=version,bytes=output.stat().st_size)))
