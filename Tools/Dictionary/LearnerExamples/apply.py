"""Apply versioned original learner examples to the bundled build artifact only.
Negative ranks are reserved for this source; WordNet rows and definitions survive.
"""
import csv
import json
from pathlib import Path
import re
import sqlite3
import sys

SOURCE = Path(__file__).with_name('examples.tsv')

def apply(connection):
    rows = list(csv.reader(SOURCE.open(encoding='utf-8'), delimiter='\t'))
    seen = set()
    counts = {}
    for word, pos, definition, example in rows:
        assert re.search(r'(?<![a-z])' + re.escape(word) + r'(?![a-z])', example.lower()), (word, example)
        assert example not in seen, example
        seen.add(example)
        assert connection.execute('select 1 from word where wl=?', (word,)).fetchone(), word
        counts[word] = counts.get(word, 0) + 1
        rank = -100 + counts[word]
        connection.execute('insert into sense(wl,rank,pos,definition,examples,synonyms) values(?,?,?,?,?,NULL) on conflict(wl,pos,rank) do update set definition=excluded.definition,examples=excluded.examples,synonyms=NULL',
                           (word, rank, pos, definition, json.dumps([example], ensure_ascii=False)))
    connection.execute("insert or replace into metadata values('learner_examples_version','1')")
    connection.execute("insert or replace into metadata values('learner_examples_source','LingoTrip original learner examples; agent-authored and reviewed; 2026-09-20')")
    return {'words': len(counts), 'examples': len(rows)}

if __name__ == '__main__':
    with sqlite3.connect(sys.argv[1]) as connection:
        print(json.dumps(apply(connection)))
