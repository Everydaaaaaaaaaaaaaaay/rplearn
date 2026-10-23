#!/usr/bin/env python3
"""Serialize explicitly authored passages/questions; never invent content or answer keys."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT / 'Backend/config/learning/expansions/2026-10-24'


def digest(value):
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(raw.encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('batch')
    parser.add_argument('--revise-draft', action='store_true', help='Only before first publication; database immutable hashes still prevent version replacement')
    args = parser.parse_args()
    if len(args.batch) != 4 or args.batch[0] != 'b' or not args.batch[1:].isdigit():
        raise ValueError('Expected b000-style batch')
    source = json.loads((DIRECTORY / f'{args.batch}.source.json').read_text())
    originals = {e['unit']['id']: e['unit'] for e in json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())['units']}
    entries = []
    for draft in source['units']:
        unit_id = 'expansion.20261024.' + draft['id']
        reviewed_source = originals[draft['sourceUnitId']]
        if reviewed_source['level'] != draft['level']:
            raise ValueError('Do not silently transfer a source to another level')
        questions = []
        components = []
        for part in draft['materials']:
            part_family = part.get('family', draft['family'])
            part_source = originals[part.get('sourceUnitId', draft['sourceUnitId'])]
            if part_source['level'] != draft['level']:
                raise ValueError('Every component source must match the authored level')
            material = part['title'] + '\n\n' + part['text']
            part_ids = []
            for number, item in enumerate(part['questions'], 1):
                qid = f"{unit_id}.{part['id']}.q{number}"
                part_ids.append(qid)
                question = dict(
                    id=qid, goalId='original.' + part_family,
                    instruction=(item.get('instruction') or part.get('instruction') or draft.get('instruction') or ('看图，选择与英文词组对应的图片。' if draft['level'] == 'primary1' else '选择合适的应答。' if draft['level'] == 'primary2' and draft['family'] == 'function_choice' else 'Read the complete material and choose the best answer.')),
                    prompt=item['prompt'], material=material,
                    explanation=item['explanation'],
                    hint='Use the complete material and the question together.',
                    difficultyReason='New provisional original for this level; no independent learner calibration claimed.',
                )
                if part_family == 'passage_form':
                    if not item.get('acceptedAnswers') or not item.get('marking'):
                        raise ValueError('Explicit accepted variants and bounded marking required')
                    question.update(type='completion', acceptedAnswers=item['acceptedAnswers'],
                        normalization=dict(ignoreCase=True, ignoreTerminalPunctuation=False), marking=item['marking'])
                else:
                    options = item.get('options', part.get('candidates', []))
                    if len(options) < 2 or not 0 <= item['answer'] < len(options):
                        raise ValueError('Invalid hand-authored candidate set or key')
                    question.update(type='choice',
                        options=[dict(id=f'o{i}', text=text, **({'imageAssetId': item['optionImages'][i]} if 'optionImages' in item else {})) for i, text in enumerate(options)],
                        answer=f"o{item['answer']}")
                questions.append(question)
            component_family = part_family if part_family in ('choice_cloze', 'shared_insertion', 'passage_form') else 'reading_choice'
            components.append(dict(id=f"{unit_id}#{part['id']}", family=component_family, questionIds=part_ids,
                sourceNumbers=list(range(1, len(part_ids) + 1)), sourceUnitId=unit_id, sourceContentHash=digest(part)))
        senior = draft['level'].startswith('senior')
        if senior:
            if draft['family'] == 'choice_cloze':
                if len(components) != 1 or len(questions) != 15 or any(len(q['options']) != 4 for q in questions):
                    raise ValueError('Senior cloze needs a complete 15-gap passage')
                for number in range(1, 16):
                    if draft['materials'][0]['text'].count(f'____{number}____') != 1:
                        raise ValueError('Every cloze gap must appear exactly once in the full passage')
            elif draft['family'] == 'shared_insertion_passage_form':
                if [c['family'] for c in components] != ['shared_insertion', 'passage_form']:
                    raise ValueError('Mixed practice needs full insertion followed by full passage form')
                insertion, form = draft['materials']
                if len(insertion['questions']) != 5 or len(form['questions']) != 10:
                    raise ValueError('Mixed practice needs all 5 and 10 scoring items')
                candidates = insertion['questions'][0].get('options', insertion.get('candidates', []))
                if len(candidates) != 7 or len(set(candidates)) != 7 or any(q.get('options', insertion.get('candidates', [])) != candidates for q in insertion['questions']):
                    raise ValueError('Insertion must share seven distinct full candidates')
                if len({q['answer'] for q in insertion['questions']}) != 5:
                    raise ValueError('Insertion needs five different answers and two unused options')
                for part, total in ((insertion, 5), (form, 10)):
                    for number in range(1, total + 1):
                        if part['text'].count(f'____{number}____') != 1:
                            raise ValueError('Every mixed-practice gap must appear exactly once')
            elif len(components) != 2 or any(len(c['questionIds']) not in (3, 4) for c in components):
                raise ValueError('Senior reading practice needs two complete 3/4-question passages')
        material = '\n\n'.join(part['title'] + '\n\n' + part['text'] for part in draft['materials'])
        source_hash = digest(draft)
        author_check = dict(boundary=source['reviewBoundary'], questions=[dict(id=q['id'], key=q.get('answer', q.get('acceptedAnswers')), rationale=q['explanation']) for q in questions])
        references = copy.deepcopy(reviewed_source['references'])
        for reference in references:
            reference['alignment'] = (draft.get('alignmentNote') or ('Uses the recorded source for task and marking rules only. New text/questions and practice grouping; source sample count is not increased. ' + reference['alignment']))[:500]
        if senior:
            cloze = draft['family'] == 'choice_cloze'
            mixed = draft['family'] == 'shared_insertion_passage_form'
            references.insert(0, dict(sourceId='gaokao.2025.national1', unit='2025 National I insertion and passage-form task structure' if mixed else '2025 National I complete cloze task structure' if cloze else '2025 National I complete reading task structure', pages='Reading: five of seven; Use of English: 10-gap passage form' if mixed else 'Use of English: 15-gap cloze' if cloze else 'Reading section', alignment='One full five-gap passage sharing seven candidates, plus one full ten-gap grammar passage. Source supplies task rules only; all prose and keys are original.' if mixed else 'One complete original 15-gap passage, four options per gap; the source supplies task rules, not copied text or keys.' if cloze else 'Two complete original readings; the source paper supplies task rules, not copied text or answer keys.'))
        notice = '2026-10-24新题批次 ' + args.batch + '；原创候选，非高考真题；自审及程序检查，不声称独立教师或学生稳定性验证。'
        unit = dict(id=unit_id, version=1, schemaVersion=1, scoringVersion=1, roleKey='companion', roleVersion=1,
            level=draft['level'], title=('高考题型原创 · 10·24新题 · ' if senior else '10·24新题 · ') + draft['title'],
            summary=draft['title'] + f"，共{len(questions)}题。", scene='先阅读完整材料，再按题目要求作答。',
            estimatedMinutes=draft['minutes'], goalIds=list(dict.fromkeys(q['goalId'] for q in questions)), prerequisiteGoalIds=[],
            references=references, authorship=dict(kind='authored', author='Codex 2026-10-24 new authoring', reviewedBy='Same author content review; not independent teacher review', reviewedAt='2026-10-24', reviewNotes=source['reviewBoundary']),
            beats=[], originalGroup=dict(id=unit_id, family=draft['family'], label=draft['title'],
                candidateSHA256=source_hash, authorCheckSHA256=digest(author_check), sourceGroupIds=[c['id'] for c in components], sourceNotice=notice, material=material), questions=questions)
        entry = dict(unit=unit, contentHash=digest(unit), reviewNotes=source['reviewBoundary'] + ' 每道题保存了正确键和所有干扰项的具体辨析。')
        if senior:
            entry['components'] = components
        entries.append(entry)
    manifest = dict(version=1, run='2026-10-24', batch=args.batch, createdAt=source['createdAt'], entries=entries)
    if source.get('imageAssets'):
        manifest['imageAssets'] = source['imageAssets']
    target = DIRECTORY / f'{args.batch}.json'
    if target.exists() and json.loads(target.read_text()) != manifest and not args.revise_draft:
        raise ValueError('Frozen batch already exists with different content; create a new batch')
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    index_path = DIRECTORY / 'index.json'
    index = json.loads(index_path.read_text())
    if args.batch not in index['batches']:
        index['batches'].append(args.batch)
    if any(e['unit']['level'].startswith('senior') for e in entries):
        if args.batch not in index.setdefault('gaokaoBatches', []):
            index['gaokaoBatches'].append(args.batch)
    index_path.write_text(json.dumps(index, indent=2) + '\n')
    print(json.dumps(dict(batch=args.batch, units=len(entries), questions=sum(len(e['unit']['questions']) for e in entries), hash=digest([manifest]))))


if __name__ == '__main__':
    main()
