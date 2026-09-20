"""Export the exact top-5000 display shortfall. Generation runs separately."""
import collections
import importlib.util
import json
from pathlib import Path
import sqlite3

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('seed', ROOT / 'Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py')
seed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(seed)

def export():
    db = sqlite3.connect(f'file:{ROOT}/App/Resources/learner_dictionary.sqlite?mode=ro', uri=True)
    db.row_factory = sqlite3.Row
    jobs = list(seed.iter_jobs(db))
    by_word = collections.defaultdict(list)
    for job in jobs:
        by_word[job['lemma']].append(job['sentence'])
    return [dict(lemma=w['wl'], rank=w['seed_rank'], meanings=w['translation'], count=2-len(by_word[w['wl']]), existing=by_word[w['wl']])
            for w in seed.iter_top_words(db) if len(by_word[w['wl']]) < 2]

if __name__ == '__main__':
    import sys
    Path(sys.argv[1]).write_text(json.dumps(export(), ensure_ascii=False, indent=2))
