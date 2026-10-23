#!/usr/bin/env python3
"""Export exact-content-bound display corrections without changing frozen grading."""
import hashlib
import json
import re
import subprocess
from pathlib import Path
from learning_language_revisions import PROMPTS, CHARACTER_PROMPTS, OPTIONS, CHARACTER_OPTIONS

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / 'Backend/config/learning'
HAN = re.compile(r'[\u3400-\u9fff]')


def digest(question):
    # Same canonical JSON as contentHash; only the local/composed ID may vary.
    body = {k: v for k, v in question.items() if k != 'id'}
    return hashlib.sha256(json.dumps(body, ensure_ascii=False, sort_keys=True,
                                    separators=(',', ':')).encode()).hexdigest()


def main():
    entries = {}
    reviewed = []

    def add(unit_id, q, prompt, choices=None):
        assert not HAN.search(prompt)
        patch = {'sourceHash': digest(q), 'sourceUnitId': unit_id,
                 'sourceQuestionId': q['id'], 'prompt': prompt}
        if choices is not None:
            assert len(choices) == len(q['options'])
            assert all(not HAN.search(t) for t in choices)
            patch['options'] = [{'id': o['id'], 'text': t}
                                for o, t in zip(q['options'], choices)]
        if patch['sourceHash'] in entries:
            assert entries[patch['sourceHash']]['prompt'] == prompt
        else:
            entries[patch['sourceHash']] = patch

    units = [json.loads(p.read_text()) for p in sorted((CONFIG / 'units').glob('*.json'))]
    for u in units:
        if u['level'].startswith('primary'):
            continue
        for q in u['questions']:
            if q['type'] != 'choice':
                continue
            prompt = CHARACTER_PROMPTS.get(u['id'], {}).get(q['id'], PROMPTS.get(q['id']))
            assert prompt, (u['id'], q['id'])
            choices = CHARACTER_OPTIONS.get((u['id'], q['id']), OPTIONS.get(q['id']))
            if any(HAN.search(o['text']) for o in q['options']):
                assert choices is not None, (u['id'], q['id'])
            add(u['id'], q, prompt, choices)
            reviewed.append((u['id'], q['id']))

    # Existing attempts may predate the first listening rollout. Reuse the exact
    # already-reviewed translation only when type, choices and answer IDs agree.
    old = '9edd518d^'
    listening = 0
    for u in units:
        name = f"Backend/config/learning/units/{u['id']}.json"
        historical = json.loads(subprocess.check_output(['git', 'show', f'{old}:{name}'], cwd=ROOT))
        for q in historical['questions']:
            new = next(n for n in u['questions'] if n['id'] == q['id'])
            if q['type'] != 'listeningChoice' or new['type'] != q['type']:
                continue
            if HAN.search(new['prompt']) or not HAN.search(q['prompt'] + ''.join(o['text'] for o in q['options'])):
                continue
            assert q['answer'] == new['answer'] and q['audio'] == new['audio']
            assert [o['id'] for o in q['options']] == [o['id'] for o in new['options']]
            add(u['id'], q, new['prompt'], [o['text'] for o in new['options']])
            listening += 1

    originals = json.loads((CONFIG / 'originals/catalog.json').read_text())
    labels = 0
    for entry in originals['units']:
        u = entry['unit']
        if u['level'] in ('primary1', 'primary2'):
            continue
        for q in u['questions']:
            if q['type'] not in ('choice', 'listeningChoice'):
                continue
            choices = []
            for o in q['options']:
                t = o['text']
                # Labels only. Substantive Chinese is never machine-translated.
                m = re.fullmatch(r'([A-Z√×][.、]\s*)(正确|与短文一致|一致|相符|错误|与短文不一致|不一致|不相符)', t)
                if m:
                    t = m[1] + ('True' if m[2] in ('正确', '与短文一致', '一致', '相符') else 'False')
                m = re.fullmatch(r'([A-Z])[.、]?\s*(?:图片|图)([A-Z])', t)
                if m:
                    t = f'{m[1]}. Picture {m[2]}'
                m = re.fullmatch(r'([A-Z])[.、]?\s*选项\s*([A-Z])', t)
                if m:
                    t = f'{m[1]}. Option {m[2]}'
                m = re.fullmatch(r'([A-Z])[.、]?\s*活动\s*([A-Z])', t)
                if m:
                    t = f'{m[1]}. Activity {m[2]}'
                choices.append(t)
            prompt = re.sub(r'^([A-Z])组\s*·\s*', r'Part \1: ', q['prompt'])
            if choices == [o['text'] for o in q['options']] and prompt == q['prompt']:
                continue
            prompt = re.sub(r'^第(\d+)图与所听句子(?:一致|相符)吗？$', r'Does picture \1 match what you hear?', prompt)
            prompt = re.sub(r'^第(\d+)空$', r'Gap \1', prompt)
            prompt = re.sub(r'^第(\d+)件事对应哪幅图？$', r'Which picture shows event \1?', prompt)
            if choices == [o['text'] for o in q['options']] and prompt == q['prompt']:
                continue
            assert not HAN.search(prompt), (u['id'], q['id'], prompt)
            if any(HAN.search(t) for t in choices):
                # These are deliberate vocabulary translations, not gloss options.
                assert 'mean in Chinese?' in prompt, (u['id'], q['id'], choices)
                add(u['id'], q, prompt)
            else:
                add(u['id'], q, prompt, choices)
            labels += 1

    # Separately published bank revision, discovered by the read-only online audit.
    # Bind its full private content hash, never its reusable local question number.
    bank_revision = {
        'sourceHash': '03a2dd20480507780b7dc09ebc08d2092574275702e0ae4e4f7d051dff143fdf',
        'sourceUnitId': 'ruby.senior3.coastal-display-captions',
        'sourceQuestionId': 'q1',
        'prompt': "A visitor photographed a boat washed onto the beach by the waves. Which statement matches the sentence? 'Washed onto' means carried onto land by water.",
        'options': [
            {'id': 'a', 'text': 'A visitor photographed a boat that had been washed onto the beach by the waves.'},
            {'id': 'b', 'text': 'The waves washed a boat onto the beach only after a visitor photographed it.'},
            {'id': 'c', 'text': 'A visitor photographed a boat while the visitor was being washed onto the beach.'},
        ],
    }
    updates = json.loads((CONFIG / 'bank-revisions/2026-10-11-cross-question.json').read_text())['updates']
    bank_source = next(u['question']['question'] for u in updates
                       if u['unitId'] == bank_revision['sourceUnitId']
                       and u['localQuestionId'] == bank_revision['sourceQuestionId'])
    assert digest(bank_source) == bank_revision['sourceHash']
    entries[bank_revision['sourceHash']] = bank_revision

    output = {'version': 1, 'reviewedAt': '2026-10-23',
              'reviewNotes': 'Codex逐题复核初中至高级独立选择题英文语义、条件、否定及干扰项；复用上一轮听力译文；仅转换完整题组固定标签。保留原选项身份、原始快照、判分与历史成绩；非独立教研或学生效度验证。',
              'entries': sorted(entries.values(), key=lambda e: e['sourceHash'])}
    (CONFIG / 'presentation-revisions.json').write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'reviewedChoices': len(reviewed), 'legacyListening': listening,
                      'originalLabelQuestions': labels, 'exactContentBindings': len(entries)}))


if __name__ == '__main__':
    main()
