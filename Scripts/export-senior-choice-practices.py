#!/usr/bin/env python3
"""Export only reviewed, complete senior multiple-choice groups. Never author new items."""
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def main():
    source = json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())
    entries = []
    for entry in source['units']:
        original = entry['unit']
        if original['level'] not in ['senior1', 'senior2', 'senior3'] or original['originalGroup']['family'] != 'sentence_choice':
            continue
        assert digest(original) == entry['contentHash']
        assert len(original['questions']) in [15, 20]
        assert all(q['type'] == 'choice' and len(q['options']) == 4 for q in original['questions'])
        for question in original['questions']:
            assert {p['outcome'] for p in entry['probes'] if p['questionId'] == question['id']} >= {'correct', 'incorrect'}
        unit = copy.deepcopy(original)
        identity = hashlib.sha256(original['id'].encode()).hexdigest()[:20]
        unit['id'] = f"gaokao.single-choice.{original['level']}.{identity}"
        unit['title'] = '高中客观专项 · 单项选择 · ' + original['title'][:65]
        unit['summary'] = f"完整{len(original['questions'])}题单项选择；词汇、语法及交际用语，按地区卷型标注。"
        for question in unit['questions']:
            question['id'] = f"senior.choice.{identity}.{question['id']}"
            question['material'] = original['originalGroup']['material']
        group = unit['originalGroup']
        group.update(id=unit['id'], label='单项选择', sourceGroupIds=[original['id'] + '#whole'],
                     sourceNotice=group['sourceNotice'] + ' 完整单项选择专项；天津等地区卷型，不声称全国卷均设此节。')
        entries.append({'unit': unit, 'contentHash': digest(unit), 'sourceUnitId': original['id'], 'sourceContentHash': entry['contentHash']})
    assert len(entries) == 9
    path = ROOT / 'Backend/config/learning/gaokao/single-choice.json'
    path.write_text(json.dumps({'version': 1, 'entries': entries}, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'groups': len(entries), 'questions': sum(len(e['unit']['questions']) for e in entries)}))


if __name__ == '__main__':
    main()
