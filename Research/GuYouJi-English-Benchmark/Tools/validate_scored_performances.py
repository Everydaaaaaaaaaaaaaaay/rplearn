#!/usr/bin/env python3
"""Check private research performances without inferring unpublished scores.

Source/page references and arithmetic consistency do not validate ratings,
pairing semantics, transcription accuracy, rights or educational suitability.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator

from validate_item_groups import acquired_content_metadata

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]
SCHEMA = BASE / 'Performances/ScoredPerformance.schema.json'


def inspect_performance(record, sources, acquisitions, check_assets=False):
    schema = json.loads(SCHEMA.read_text())
    Draft202012Validator.check_schema(schema)
    errors = [f'{list(e.path)}: {e.message}' for e in
              Draft202012Validator(schema).iter_errors(record)]

    def require(condition, message):
        if not condition:
            errors.append(message)

    if not errors:
        def index(rows, label):
            result = {}
            for row in rows:
                require(row['id'] not in result, f'{label}: duplicate ID {row["id"]}')
                result[row['id']] = row
            return result

        refs = index(record['references'], 'reference')
        scales = index(record['scales'], 'scale')
        scores = index(record['scores'], 'score')
        criteria = index(record['criteria'], 'criterion')

        def reference_ids(ids, role=None):
            require(set(ids) <= refs.keys(), 'Unknown reference ID')
            if role:
                require(all(refs.get(i, {}).get('role') == role for i in ids),
                        f'Reference has wrong role for {role}')

        for ref in refs.values():
            require(not ref['full_transcription'] or ref['transcription_status'] == 'verified',
                    f'{ref["id"]}: full transcription without verified transcription')
            origin = ref['origin']
            if origin['kind'] == 'source_record':
                sid, aid = origin['source_id'], origin['acquisition_id']
                require(sid in sources, f'{ref["id"]}: unknown source')
                require(aid in sources.get(sid, {}).get('acquisition_ids', []),
                        f'{ref["id"]}: acquisition not associated with source')
                row = acquisitions.get(aid, {})
                ready = acquired_content_metadata(row)
                require(ready, f'{ref["id"]}: source missing nonempty parsed content')
                if check_assets and ready:
                    path = (REPO / row['path']).resolve()
                    safe = (REPO / 'build').resolve() in path.parents
                    require(safe and path.is_file(), f'{ref["id"]}: missing/outside-cache asset')
                    if safe and path.is_file():
                        payload = path.read_bytes()
                        require(len(payload) == row['bytes'] and
                                hashlib.sha256(payload).hexdigest() == row['sha256'],
                                f'{ref["id"]}: asset digest/size mismatch')
                        if path.suffix == '.pdf':
                            from pypdf import PdfReader
                            try:
                                page_count = len(PdfReader(path).pages)
                                require(max(origin['pdf_pages']) <= page_count,
                                        f'{ref["id"]}: PDF locator outside source pages')
                            except Exception as exc:
                                require(False, f'{ref["id"]}: PDF parser failure {type(exc).__name__}')
                        else:
                            require(False, f'{ref["id"]}: PDF locator on non-PDF acquisition')

        prompt = record['prompt']
        reference_ids(prompt['text_ref_ids'], 'prompt_text')
        reference_ids(prompt['required_visual_ref_ids'], 'required_visual')
        if prompt['status'] == 'paired':
            require(bool(prompt['text_ref_ids']), 'Paired task lacks prompt text')
            require(prompt['visual_dependency_status'] in ('acquired', 'not_required'),
                    'Paired task has unresolved required visuals')
        else:
            require(not prompt['text_ref_ids'] and not prompt['required_visual_ref_ids'],
                    'Missing prompt contains acquired prompt/visual references')
        if prompt['visual_dependency_status'] == 'acquired':
            require(bool(prompt['required_visual_ref_ids']), 'Acquired visual has no reference')
        else:
            require(not prompt['required_visual_ref_ids'], 'Visual references contradict dependency status')
        reference_ids(record['response']['ref_ids'], 'response')
        require(record['response']['errors_preserved'], 'Source errors must be preserved')
        if record['modality'] == 'written':
            require(all(refs.get(i, {}).get('representation') != 'audio' for i in
                        record['response']['ref_ids']), 'Written response cannot be audio')

        for scale in scales.values():
            lo, hi, step = scale['minimum'], scale['maximum'], scale['increment']
            require(all(math.isfinite(v) for v in [lo, hi] + ([] if step is None else [step])),
                    'Nonfinite scale bound or increment')
            require(lo < hi, 'Scale bounds reversed or empty')
            known = scale['version_status'] == 'source_identified'
            require(known == (scale['version'] is not None), 'Scale version contradicts status')
        task_scores = []
        for score in scores.values():
            reference_ids(score['evidence_ref_ids'], 'published_score')
            require(score['scale_id'] in scales, 'Unknown score scale')
            scale = scales.get(score['scale_id'])
            value = score['value']
            require(math.isfinite(value), 'Nonfinite score value')
            if scale:
                require(scale['minimum'] <= value <= scale['maximum'], 'Score outside scale')
                step = scale['increment']
                if step is not None and math.isfinite(value):
                    offset = (value - scale['minimum']) / step
                    require(math.isfinite(offset) and abs(offset - round(offset)) < 1e-8,
                            'Score not on declared scale increment')
            if score['scope'] == 'criterion':
                require(score['criterion_id'] in criteria, 'Unknown score criterion')
                criterion = criteria.get(score['criterion_id'], {})
                require(criterion.get('status') == 'published' and
                        criterion.get('score_id') == score['id'], 'Criterion/score relation mismatch')
            else:
                require(score['criterion_id'] is None, 'Noncriterion score names a criterion')
            if score['scope'] == 'task':
                task_scores.append(score)
            expected = 'source_record' if score['score_origin'] == 'published_source' else 'original_fixture'
            require(all(refs.get(i, {}).get('origin', {}).get('kind') == expected
                        for i in score['evidence_ref_ids']), 'Score origin contradicts evidence')
        require(bool(task_scores), 'Single-task performance lacks an explicit task score')
        require(all(score['scope'] in ('task', 'criterion') for score in scores.values()),
                'Single-task performance cannot substitute section/overall rating')
        require(len({(x['scope'], x['criterion_id'], x['scale_id']) for x in scores.values()}) ==
                len(scores), 'Duplicate score scope/criterion/scale')
        for criterion in criteria.values():
            if criterion['status'] == 'not_published':
                require(criterion['score_id'] is None, 'Unpublished criterion has score')
            else:
                score = scores.get(criterion['score_id'], {})
                require(score.get('scope') == 'criterion' and
                        score.get('criterion_id') == criterion['id'], 'Published criterion lacks matching score')
        rubric = record['rubric']
        reference_ids(rubric['reference_ref_ids'], 'rubric_reference')
        require((rubric['scoring_version_status'] == 'source_identified') ==
                (rubric['scoring_version'] is not None), 'Applied rubric version contradicts status')
        if rubric['historical_match_status'] == 'source_established':
            require(rubric['scoring_version_status'] == 'source_identified' and
                    bool(rubric['reference_ref_ids']), 'Historical rubric match lacks source/version')
        review = record['review']
        for role in ('independent', 'learner_calibration'):
            ids = review[role + '_evidence_ref_ids']
            reference_ids(ids, role + '_record')
            if review[role] == 'documented':
                require(bool(ids) and all(refs.get(i, {}).get('origin', {}).get('kind') ==
                                         'source_record' for i in ids),
                        'Authored fixture cannot establish reviewer/learner evidence')
            else:
                require(not ids, 'Not-performed review has evidence')
        rights = record['rights']
        reference_ids(rights['scope_evidence_ref_ids'], 'rights_scope_record')
        if rights['status'] == 'documented_scope':
            require(bool(rights['scope_evidence_ref_ids']) and all(
                refs.get(i, {}).get('origin', {}).get('kind') == 'source_record'
                for i in rights['scope_evidence_ref_ids']), 'Rights scope lacks source evidence')

    return dict(id=record.get('id'), structure_valid=not errors, errors=errors,
                production_admission=False, gold_admission=False,
                limitation='References/arithmetic only; no inferred criterion scores, authenticated rating, semantic pairing, rights or calibration')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('paths', nargs='*', type=Path)
    parser.add_argument('--check-assets', action='store_true')
    args = parser.parse_args()
    sources = {x['id']: x for x in json.loads((BASE / 'Registry/sources.json').read_text())['sources']}
    acquisitions = {x['id']: x for x in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    paths = args.paths or sorted((BASE / 'Performances/Fixtures').glob('*.json'))
    results = [inspect_performance(json.loads(p.read_text()), sources, acquisitions, args.check_assets)
               for p in paths]
    print(json.dumps(results, ensure_ascii=False, indent=2))
    raise SystemExit(0 if all(x['structure_valid'] for x in results) else 1)


if __name__ == '__main__':
    main()
