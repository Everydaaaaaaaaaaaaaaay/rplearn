#!/usr/bin/env python3
"""Structural checks, not a claim of measured linguistic difficulty or audio QA."""
import json
import re
import sqlite3
from collections import Counter
from pathlib import Path
root = Path(__file__).resolve().parent.parent
bank = json.loads((root / 'App/Resources/Learning/listening-v1.json').read_text())
assert len(bank) == 36
assert len({q['id'] for q in bank}) == len(bank)
assert len({q['script'] for q in bank}) == len(bank)
coverage = Counter()
for q in bank:
    band = q['band']
    assert band in (1, 2, 3)
    low, high = {1:(20,40),2:(41,70),3:(71,100)}[band]
    assert low <= len(q['script'].split()) <= high, q['id']
    sentences = [s for s in re.split(r'[.!?]', q['script']) if s.strip()]
    assert len(sentences) <= {1:3,2:4,3:5}[band], q['id']
    assert max(len(s.split()) for s in sentences) <= {1:16,2:24,3:30}[band], q['id']
    assert len(q['options']) == len(set(q['options'])) == 3
    assert q['answer'] in range(3)
    assert len(q['question']) <= 35 and max(map(len, q['options'])) <= 22
    assert max(map(len, q['options'])) - min(map(len, q['options'])) <= 2, (q['id'], 'option length cue')
    assert q['explanation']
    coverage[band,q['skill']] += 1
assert len(coverage) == 9 and set(coverage.values()) == {4}
print('36 items validated: IDs, distinct scripts, lengths, options, and 3 × 3 skill coverage. Audio/psychometric calibration not implied.')

# A cheap adversarial baseline: answer without listening, using only length.
# Ties are random; this is not an estimate of learner ability or item validity.
for band in (1, 2, 3):
    questions = [q for q in bank if q['band'] == band]
    for label, extreme in [('longest', max), ('shortest', min)]:
        expected = 0
        for q in questions:
            lengths = list(map(len, q['options']))
            tied = [i for i, length in enumerate(lengths) if length == extreme(lengths)]
            expected += 1 / len(tied) if q['answer'] in tied else 0
        rate = expected / len(questions)
        assert rate <= 0.5, (band, label, rate, 'length-only shortcut requires review')
        print(f'Band {band} {label}-only expected accuracy: {rate:.3f}')

# Reuse the frozen dictionary frequency data; this is a screen, not CEFR calibration.
connection = sqlite3.connect(f"file:{root / 'App/Resources/learner_dictionary.sqlite'}?mode=ro", uri=True)
ranks = {}
forms = {}
for word, bnc, frq, exchange in connection.execute('select wl,bnc,frq,exchange from word'):
    ranks[word] = min([rank for rank in (bnc, frq) if rank > 0], default=999999)
    for part in (exchange or '').split('/'):
        if ':' in part:
            for form in part.split(':', 1)[1].split(','):
                forms.setdefault(form, []).append(word)
for form, lemma in connection.execute('select form,lemma from lemma'):
    forms.setdefault(form, []).append(lemma)
for form, lemma in {'am':'be','is':'be','are':'be','was':'be','were':'be','been':'be','has':'have','had':'have','did':'do','does':'do'}.items():
    forms.setdefault(form, []).append(lemma)
coverage = {}
for question in bank:
    text = question['script'].lower().replace('cannot', 'can not')
    text = re.sub(r"[’']s\b", '', text)
    words = re.findall('[a-z]+', text)
    token_ranks = [min([ranks.get(word,999999)] + [ranks.get(lemma,999999) for lemma in forms.get(word,[])]) for word in words]
    limit = {1:2000,2:3000,3:5000}[question['band']]
    ratio = sum(rank <= limit for rank in token_ranks) / len(words)
    assert ratio >= .9, (question['id'], ratio)
    coverage.setdefault(question['band'], []).append(ratio)
print('Minimum frequent-token coverage by band:', {band: round(min(values),3) for band,values in coverage.items()})
