#!/usr/bin/env python3
"""Check complete variable clozes and frozen showcase payload, without a model."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from showcase_extended_tasks import extract_variable_cloze

BASE = Path(__file__).resolve().parents[1]


def check(page, baseline_hash):
    data = json.loads(re.search(r'<script id="showcase-data" type="application/json">(.*?)</script>', page.read_text(), re.S)[1])
    selection = json.loads((BASE / 'FirstRelease/showcase-selection-v0.4.json').read_text())
    ids = [r['id'] for r in selection['items']]
    old = [r for r in data if r['id'] in ids]
    if [r['id'] for r in old] != ids or hashlib.sha256(json.dumps(old, ensure_ascii=False, sort_keys=True).encode()).hexdigest() != baseline_hash:
        raise ValueError('Frozen 28 showcase payload changed')
    cases = [{'case': 'frozen28payload unchanged', 'passed': True}]
    for row in data[28:]:
        candidate = (BASE / row['candidate']['path']).read_text()
        audit = json.loads((BASE / row['author_check']['path']).read_text())
        student, review = candidate.split('## 学生区\n', 1)[1].split('## 作者区\n', 1)
        n = audit['questions']
        material, questions = extract_variable_cloze(student, review, audit, n)
        if material != row['passage'] or json.loads(json.dumps(questions)) != row['questions']:
            raise ValueError('Displayed cloze differs from checked source')
        cases.append({'case': row['id'] + ': full material/choices/key/rationale', 'passed': True,
                      'responses': n, 'options': sum(len(q['options']) for q in questions)})
        changes = []
        changes.append(('truncated response list', re.sub(r'^' + str(n) + r'\. .+$', '', student, flags=re.M), review, audit, n))
        changes.append(('missing last material slot', re.sub(r'\(' + str(n) + r'\)\s*_+|_+' + str(n) + r'_+', 'MISSING', student), review, audit, n))
        changes.append(('repeated slot number', re.sub(r'\(' + str(n) + r'\)\s*_+|_+' + str(n) + r'_+', '(1) ____', student), review, audit, n))
        changes.append(('smaller count cannot truncate complete task', student, review, audit, min(n - 1, 6)))
        bad = copy.deepcopy(audit)
        key = 'author_answer_vector' if 'author_answer_vector' in bad else 'complete_author_vector'
        bad[key][0] = 'Z'
        changes.append(('out-of-bank key', student, review, bad, n))
        changes.append(('missing final rationale', student, re.sub(r'^\| ' + str(n) + r' [A-D].+$', '', review, flags=re.M), audit, n))
        changes.append(('choice removed', student.replace('A. ', 'X. ', 1), review, audit, n))
        changes.append(('rationale key drift', student, re.sub(r'^\| 1 [A-D]', '| 1 Z', review, count=1, flags=re.M), audit, n))
        for label, s, r, a, size in changes:
            try:
                extract_variable_cloze(s, r, a, size)
            except ValueError as error:
                cases.append({'case': row['id'] + ': reject ' + label, 'passed': True, 'reason': str(error)})
            else:
                raise ValueError('Invalid input admitted: ' + row['id'] + ': ' + label)
    if len(data) != 32 or sum(len(r['questions']) for r in data) != 228:
        raise ValueError('Unexpected display totals')
    return {'cases': cases, 'controls': len(cases), 'positive': 5, 'rejection': 32,
            'groups': 32, 'response_positions': 228, 'new_display_groups': 4,
            'new_display_response_positions': 34, 'new_display_options': 130,
            'frozen28canonical_sha256': baseline_hash, 'model_called': False,
            'student_independent_gold_commercial_or_production_validation': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--page', type=Path, required=True)
    parser.add_argument('--baseline-hash', required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.page, args.baseline_hash)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: v for k, v in result.items() if k != 'cases'}, ensure_ascii=False))
