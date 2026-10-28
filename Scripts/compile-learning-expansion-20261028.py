#!/usr/bin/env python3
"""Freeze explicitly authored, SHA-bound author-reviewed text tasks for the 2026-10-28 run."""
import argparse
import copy
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
RUN = '2026-10-28'
DIRECTORY = ROOT / 'Backend/config/learning/expansions' / RUN
NAMESPACE = 'expansion.20261028.'
TEXT_FAMILIES = {'passage_form', 'open_cloze', 'context_word_completion', 'keyword_transformation', 'sentence_form', 'sentence_transformation'}


def digest(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def bind_source(originals, source_id, level, family):
    original = originals.get(source_id)
    if not original or original['level'] != level or original.get('originalGroup', {}).get('family') != family:
        raise ValueError(f'Original source binding must match level and family: {source_id}/{level}/{family}')
    return original


def nonempty(value, label):
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f'Explicit {label} required')
    return value


def english(value):
    nonempty(value, 'English instruction')
    if re.search('[一-鿿]', value) or not re.search('[A-Za-z]', value):
        raise ValueError('English instructions required')
    return value


def compile_manifest(source_bytes, review_bytes, originals, batch):
    if not re.fullmatch(r'b[0-9]{3}', batch):
        raise ValueError('Expected b000-style batch')
    source, review = json.loads(source_bytes), json.loads(review_bytes)
    source_sha = hashlib.sha256(source_bytes).hexdigest()
    if review.get('sourceSHA256') != source_sha:
        raise ValueError('Review source SHA256 does not match exact source bytes')
    if review.get('reviewKind') != 'author-self-review' or not review.get('reviewer'):
        raise ValueError('Explicit author-self-review and reviewer required')
    drafts = source.get('units', [])
    if not 1 <= len(drafts) <= 30:
        raise ValueError('One bounded batch needs 1 to 30 explicitly authored units')
    draft_ids = [u['id'] for u in drafts]
    reviewed = review.get('units', [])
    if len(set(draft_ids)) != len(draft_ids) or len(reviewed) != len(drafts) or {u['id'] for u in reviewed} != set(draft_ids) or any(u.get('status') != 'approved' or not isinstance(u.get('findings'), list) for u in reviewed):
        raise ValueError('Every unique source unit requires explicit approved review and findings')
    boundary = nonempty(source['reviewBoundary'], 'review boundary')
    if len(boundary) < 30:
        raise ValueError('Review boundary must disclose the limits of author review')
    entries = []
    for draft in drafts:
        if not re.fullmatch(r'[a-z][a-z0-9_.-]{0,74}', draft['id']):
            raise ValueError('Invalid authored unit identity')
        unit_id = NAMESPACE + draft['id']
        family, level = draft['family'], draft['level']
        materials = draft['materials']
        if not materials or len({p['id'] for p in materials}) != len(materials):
            raise ValueError('Complete, uniquely identified authored materials required')
        if not re.search('[一-鿿]', draft['title']) or re.fullmatch(r'(新题|练习|阅读|题组|原创|小学|中学|大学)[0-9一二三四五六]*', draft['title']):
            raise ValueError('Concrete Chinese topic title required')
        if not isinstance(draft['minutes'], int) or not 2 <= draft['minutes'] <= 20:
            raise ValueError('Explicit practice duration outside 2 to 20 minutes')
        if source.get('imageAssets') or any('optionImages' in q or 'audio' in q for p in materials for q in p['questions']) or family.startswith('listening'):
            raise ValueError('This text-only compiler cannot admit unverified image/listening assets')
        first_family = materials[0].get('family', family)
        original = bind_source(originals, draft['sourceUnitId'], level, first_family)
        questions, components = [], []
        for part in materials:
            part_family = part.get('family', family)
            part_source = bind_source(originals, part.get('sourceUnitId', draft['sourceUnitId']), level, part_family)
            if not re.fullmatch(r'[a-z][a-z0-9_.-]{0,30}', part['id']):
                raise ValueError('Invalid material identity')
            material = nonempty(part['title'], 'material title') + '\n\n' + nonempty(part['text'], 'complete material')
            if not part['questions']:
                raise ValueError('Authored questions required')
            question_ids = []
            for number, item in enumerate(part['questions'], 1):
                question_id = f"{unit_id}.{part['id']}.q{number}"
                if len(question_id) > 120:
                    raise ValueError('Question identity exceeds storage bound')
                question_ids.append(question_id)
                instruction = item.get('instruction') or part.get('instruction') or draft.get('instruction') or ('Read the complete material and complete each gap.' if part_family in TEXT_FAMILIES else 'Read the complete material and choose the best answer.')
                question = dict(id=question_id, goalId='original.' + part_family, instruction=english(instruction), prompt=nonempty(item['prompt'], 'question prompt'), material=material,
                    explanation=nonempty(item['explanation'], 'answer rationale'), hint='Use the complete material and the question together.', difficultyReason='New provisional original for this level; no independent learner calibration claimed.')
                if part_family in TEXT_FAMILIES:
                    answers, marking = item.get('acceptedAnswers'), item.get('marking')
                    if not answers or not marking or not isinstance(marking.get('maxWords'), int) or marking['maxWords'] < 1 or marking.get('unlisted') != 'review' or not marking.get('rejectedAnswers'):
                        raise ValueError('Explicit accepted variants and bounded marking/rejected answers required')
                    if any(not isinstance(a, str) or not a.strip() or len(a.split()) > marking['maxWords'] for a in answers):
                        raise ValueError('Accepted answer violates explicit answer bounds')
                    normalized = {a.casefold().strip() for a in answers}
                    if any(a.casefold().strip() in normalized for a in marking['rejectedAnswers']):
                        raise ValueError('Rejected answer overlaps accepted answer')
                    question.update(type='completion', acceptedAnswers=answers, normalization=dict(ignoreCase=True, ignoreTerminalPunctuation=False), marking=marking)
                else:
                    options = item.get('options', part.get('candidates', []))
                    answer = item.get('answer')
                    if not 2 <= len(options) <= 7 or any(not isinstance(o, str) or not o.strip() for o in options) or len(set(options)) != len(options) or type(answer) is not int or not 0 <= answer < len(options):
                        raise ValueError('Invalid explicit candidate set or answer key')
                    if re.search('[一-鿿]', question['prompt'] + ''.join(options)):
                        raise ValueError('English choice prompt and options required')
                    for i in range(len(options)):
                        if not re.search(r'(?<![A-Za-z])' + chr(65 + i) + r'(?![A-Za-z])', item['explanation']):
                            raise ValueError('Every option, including each distractor, needs an explicit letter-bound rationale')
                    question.update(type='choice', options=[dict(id=f'o{i}', text=text) for i, text in enumerate(options)], answer=f'o{answer}')
                questions.append(question)
            component_family = part_family if part_family in {'choice_cloze', 'shared_insertion', 'passage_form'} else 'reading_choice'
            components.append(dict(id=f"{part_source['id']}#{draft['id']}.{part['id']}", family=component_family, questionIds=question_ids, sourceNumbers=list(range(1, len(question_ids) + 1)), sourceUnitId=part_source['id'], sourceContentHash=digest(part_source)))
        senior = bool(re.fullmatch(r'senior[123]', level))
        if senior:
            families = [c['family'] for c in components]
            counts = [len(c['questionIds']) for c in components]
            if draft['minutes'] < 14 or not ((families == ['reading_choice', 'reading_choice'] and all(n in (3, 4) for n in counts)) or (families == ['choice_cloze'] and counts == [15]) or (families == ['shared_insertion', 'passage_form'] and counts == [5, 10])):
                raise ValueError('Senior practice requires complete reviewed Gaokao task components')
            for part, component in zip(materials, components):
                if component['family'] in {'choice_cloze', 'shared_insertion', 'passage_form'}:
                    if any(part['text'].count(f'____{n}____') != 1 for n in range(1, len(part['questions']) + 1)):
                        raise ValueError('Every senior gap must occur exactly once')
                if component['family'] in {'choice_cloze', 'reading_choice'} and any(len(q.get('options', part.get('candidates', []))) != 4 for q in part['questions']):
                    raise ValueError('Senior reading/cloze requires four candidates per item')
                if component['family'] == 'shared_insertion':
                    candidates = part['questions'][0].get('options', part.get('candidates', []))
                    if len(candidates) != 7 or any(q.get('options', part.get('candidates', [])) != candidates for q in part['questions']) or len({q['answer'] for q in part['questions']}) != 5:
                        raise ValueError('Senior insertion requires seven shared candidates and five distinct keys')
        references = copy.deepcopy(original['references'])
        for reference in references:
            reference['alignment'] = (draft.get('alignmentNote') or 'Recorded source supplies level and task rules only; passage, questions and keys are newly authored. ' + reference['alignment'])[:500]
        material = '\n\n'.join(p['title'] + '\n\n' + p['text'] for p in materials)
        notice = f'{RUN}新题批次 {batch}；原创候选，非高考真题；作者自审及程序检查，不声称独立教师或学生稳定性验证。'
        unit = dict(id=unit_id, version=1, schemaVersion=1, scoringVersion=1, roleKey='companion', roleVersion=1, level=level,
            title=('高考题型原创 · ' if senior else '') + draft['title'], summary=draft['title'] + f'，共{len(questions)}题。', scene='先阅读完整材料，再按题目要求作答。', estimatedMinutes=draft['minutes'],
            goalIds=list(dict.fromkeys(q['goalId'] for q in questions)), prerequisiteGoalIds=[], references=references,
            authorship=dict(kind='authored', author='Codex 2026-10-28 explicit authoring', reviewedBy=review['reviewer'] + ' (author self-review only)', reviewedAt=RUN, reviewNotes=boundary), beats=[],
            originalGroup=dict(id=unit_id, family=family, label=draft['title'], candidateSHA256=digest(draft), authorCheckSHA256=digest(dict(sourceSHA256=source_sha, review=review)), sourceGroupIds=[c['id'] for c in components], sourceNotice=notice, material=material), questions=questions)
        entry = dict(unit=unit, contentHash=digest(unit), reviewNotes=boundary, components=components)
        entries.append(entry)
    return dict(version=1, run=RUN, batch=batch, createdAt=source['createdAt'], sourceSHA256=source_sha, reviewSHA256=hashlib.sha256(review_bytes).hexdigest(), reviewKind=review['reviewKind'], reviewer=review['reviewer'], entries=entries)


def write_manifest(manifest, directory=DIRECTORY):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    target = directory / (manifest['batch'] + '.json')
    serialized = json.dumps(manifest, ensure_ascii=False, indent=2) + '\n'
    if target.exists():
        if target.read_text() != serialized:
            raise ValueError('Frozen batch already exists with different content; create a new batch')
    else:
        with target.open('x') as output:
            output.write(serialized)
    index_path = directory / 'index.json'
    index = json.loads(index_path.read_text()) if index_path.exists() else dict(version=1, run=RUN, batches=[], gaokaoBatches=[])
    if index['run'] != RUN or len(set(index['batches'])) != len(index['batches']):
        raise ValueError('Expansion index run or batch identity mismatch')
    if manifest['batch'] not in index['batches']:
        index['batches'].append(manifest['batch'])
        index['batches'].sort()
    if any(re.fullmatch(r'senior[123]', e['unit']['level']) for e in manifest['entries']) and manifest['batch'] not in index.setdefault('gaokaoBatches', []):
        index['gaokaoBatches'].append(manifest['batch'])
        index['gaokaoBatches'].sort()
    temporary = index_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(index, indent=2) + '\n')
    temporary.replace(index_path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('batch')
    parser.add_argument('--review', type=Path, help='Defaults to SOURCE.review.json')
    args = parser.parse_args()
    review_path = args.review or args.source.with_suffix('.review.json')
    originals = {e['unit']['id']: e['unit'] for e in json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())['units']}
    manifest = compile_manifest(args.source.read_bytes(), review_path.read_bytes(), originals, args.batch)
    write_manifest(manifest)
    print(json.dumps(dict(run=RUN, batch=args.batch, units=len(manifest['entries']), questions=sum(len(e['unit']['questions']) for e in manifest['entries']), hash=digest([manifest]))))


if __name__ == '__main__':
    main()
