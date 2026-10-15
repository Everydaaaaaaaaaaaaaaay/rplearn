#!/usr/bin/env python3
"""Check visual input integrity and frozen32 payload; not student/image semantics."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path
from build_school_showcase import BASE, load_ref, extract
from showcase_visual_reading import prepare_visual_reading


def payload(path):
    return json.loads(re.search(r'<script id="showcase-data" type="application/json">(.*?)</script>', path.read_text(), re.S)[1])


def check(page):
    previous = load_ref_cache({'path': 'build/english-benchmark-research-20261012/showcase-variable-cloze-page20261015af-v0.1.html',
                              'sha256': '442b9bf1f970934e4503605fa0b562c7e7ef084f2793fe1925834cdc515303ba'})
    old, current = payload(previous), payload(page)
    if old != current[:32] or len(current) != 34 or sum(len(g['questions']) for g in current) != 234:
        raise ValueError('Frozen32 payload or new complete-group totals differ')
    cases = [{'case': 'old32payload unchanged', 'passed': True}]
    selection = json.loads((BASE / 'FirstRelease/showcase-selection-v0.6.json').read_text())
    index = json.loads(load_ref(selection['core_index']).read_text())
    for choice in selection['items'][-2:]:
        row = next(r for r in index['candidates'] if r['id'] == choice['id'])
        audit = json.loads(load_ref(row['author_check']).read_text())
        group = extract(row, choice['label'], choice['focus'], choice['visual_layout'])
        actual = prepare_visual_reading(copy.deepcopy(group), audit, choice, load_ref)
        displayed = next(g for g in current if g['id'] == row['id'])
        if json.loads(json.dumps(actual)) != displayed:
            raise ValueError('Displayed visual input differs')
        cases.append({'case': choice['visual_layout'] + ' full source/choice/media binding', 'passed': True})
        variants = []
        def add(label, mutate_group=None, mutate_audit=None):
            g, a = copy.deepcopy(group), copy.deepcopy(audit)
            if mutate_group:
                mutate_group(g)
            if mutate_audit:
                mutate_audit(a)
            variants.append((label, g, a))
        if choice['visual_layout'] == 'calendar':
            add('calendar removed', lambda g:g.update(passage=g['passage'][g['passage'].index('Our school'):]))
            add('year substituted2026', lambda g:g.update(passage=g['passage'].replace('2027','2026')))
            add('Friday moved', lambda g:g.update(passage=g['passage'].replace('| 11 | 12 | 13 | 14 | 15 | 16 | 17 |','| 11 | 12 | 13 | 14 | 16 | 15 | 17 |')))
            add('last cell missing', lambda g:g.update(passage=g['passage'].replace('| 25 | 26 | 27 | 28 | 29 | 30 |  |','| 25 | 26 | 27 | 28 | 29 |  |  |')))
            add('weekday header order', lambda g:g.update(passage=g['passage'].replace('Sunday | Monday','Monday | Sunday')))
            add('wrong registration reference', mutate_audit=lambda a:a.update(registration_previous_friday=15))
        else:
            add('fourth asset absent', mutate_audit=lambda a:a['required_image_assets'].pop())
            add('asset order swapped', mutate_audit=lambda a:a['required_image_assets'].reverse())
            add('changed image digest', mutate_audit=lambda a:a['required_image_assets'][0].update(sha256='0'*64))
            add('wrong response position', mutate_audit=lambda a:a['required_image_assets'][0].update(question_number=2))
            add('alternative description missing', lambda g:g['questions'][2]['options'].__setitem__(0,('A','![](Media/grade7-helper-A-v0.1.svg)')))
            add('wrong embedded image path', lambda g:g['questions'][2]['options'].__setitem__(0,('A',g['questions'][2]['options'][0][1].replace('helper-A','helper-B'))))
            add('three visible options', lambda g:g['questions'][2]['options'].pop())
        for label, g, a in variants:
            try:
                prepare_visual_reading(g, a, choice, load_ref)
            except ValueError as error:
                cases.append({'case': 'reject '+label, 'passed': True, 'reason': str(error)})
            else:
                raise ValueError('Invalid visual input admitted: '+label)
    return {'cases': cases, 'controls': len(cases), 'positive': 3, 'rejection': 13,
            'groups': 34, 'response_positions': 234, 'original_SVG_assets': 4,
            'new_standalone_SVG_files': 0,
            'student_independent_commercial_or_production_validation': False}


def load_ref_cache(ref):
    from grade_mode_evidence import load_ref as cache_ref
    return cache_ref(ref)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--page', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    result = check(args.page)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k != 'cases'},ensure_ascii=False))
