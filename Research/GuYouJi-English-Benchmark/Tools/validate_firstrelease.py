#!/usr/bin/env python3
"""Check frozen first-release bindings and completeness; never certify semantics."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]
DEFAULT = BASE / 'FirstRelease/review-index-v0.1.json'
TOKENS = re.compile(r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True,
                                     separators=(',', ':')).encode()).hexdigest()


def file_ref(ref):
    path = Path(ref['path'])
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('reference must be relative and contained')
    target = BASE / path
    if not target.is_file() or digest(target) != ref['sha256']:
        raise ValueError('missing file or changed digest: ' + str(path))
    return target


def passage_counts(text, extraction):
    if extraction == 'sentence_collection':
        return []
    if extraction == 'legacy_library_unmarked':
        text = text[text.index('Last month,'):text.index('\n1. ')]
        text = re.sub(r'^\*\*.*\*\*\s*$', '', text, flags=re.M)
        blocks = [text]
    else:
        blocks = re.findall(r'<!-- passage(?::[A-Z])?:start -->\n(.*?)\n'
                            r'<!-- passage(?::[A-Z])?:end -->', text, re.S)
        if not blocks:
            raise ValueError('complete passage markers missing')
    return [len(TOKENS.findall(re.sub(r'\(\d+\) _+(?: \([A-Za-z]+\))?', '', b)))
            for b in blocks]


def check(data, check_cache=False):
    errors = []
    observations = json.loads((BASE / 'FirstRelease/source-group-observations.json').read_text())
    groups = {g['id']: g for g in observations['groups']}
    registry = json.loads((BASE / 'Registry/acquisitions.json').read_text())
    acquisitions = {a['id']: a for a in registry['acquisitions']}
    grades = set(range(7, 13))
    candidates = data.get('candidates', [])
    expected_ids = data.get('selected_source_groups', [])
    seen = set()
    coverage = {g: set() for g in grades}
    families = {g: set() for g in grades}
    questions = 0
    if data.get('scope') != 'six_grade_core_author_review_package':
        errors.append('wrong release scope')
    for field in ['independent_review', 'student_calibration', 'production_admission',
                  'commercial_admission', 'full_benchmark_complete']:
        if data.get(field) is not False:
            errors.append('unsupported admission claim: ' + field)
    if len(candidates) != data.get('candidate_count') or len(expected_ids) != data.get('source_group_count'):
        errors.append('declared package counts differ')
    if len({r['id'] for r in expected_ids}) != len(expected_ids):
        errors.append('duplicate selected source group')
    for ref in expected_ids:
        g = groups.get(ref['id'])
        if not g or canonical(g) != ref['canonical_sha256']:
            errors.append('changed/missing source-group binding: ' + ref['id'])
            continue
        if g['grade'] not in grades or not g.get('complete_selected_group_reviewed'):
            errors.append('incomplete/out-of-scope source group: ' + ref['id'])
            continue
        families[g['grade']].add(g['acquisition_id'])
        if g['acquisition_id'] not in acquisitions:
            errors.append('source acquisition missing: ' + ref['id'])
    for row in candidates:
        identity = row.get('id', '?')
        try:
            if identity in seen:
                raise ValueError('duplicate candidate')
            seen.add(identity)
            if row['grade'] not in grades or row['core_kind'] not in {'reading', 'cloze', 'language'}:
                raise ValueError('grade/core kind out of scope')
            authored = json.loads(file_ref(row['author_check']).read_text())
            text = file_ref(row['candidate']).read_text()
            file_ref(row['specification_at_authoring'])
            if authored['grade'] != row['grade']:
                raise ValueError('candidate grade mismatch')
            for name, field in [('candidate', 'candidate'), ('specification_at_authoring', 'specification')]:
                if authored[field + '_path'] != row[name]['path'] or authored[field + '_sha256'] != row[name]['sha256']:
                    raise ValueError('author check does not bind actual artifact')
            if authored.get('anchor_group_ids') is None:
                legacy = row.get('legacy_binding')
                if not legacy or legacy.get('evidence') != 'explicit_anchor_id_in_candidate_body' or row['anchor_group_ids'] != legacy['anchor_group_ids']:
                    raise ValueError('legacy candidate requires explicit binding evidence')
                if not all(a in text for a in row['anchor_group_ids']):
                    raise ValueError('legacy anchor not explicit in body')
            elif authored['anchor_group_ids'] != row['anchor_group_ids']:
                raise ValueError('anchor list differs from author check')
            kind = authored.get('kind') or row['legacy_binding']['kind']
            derived_core = 'cloze' if 'cloze' in kind else 'reading' if 'reading' in kind else 'language'
            if row['core_kind'] != derived_core:
                raise ValueError('core kind does not match actual authoring mode')
            if not row['anchor_group_ids']:
                raise ValueError('no complete matching anchor')
            for anchor in row['anchor_group_ids']:
                if anchor not in groups or groups[anchor]['grade'] != row['grade']:
                    raise ValueError('wrong-grade/missing anchor')
                if anchor not in {r['id'] for r in expected_ids}:
                    raise ValueError('anchor outside frozen package')
                source = groups[anchor]
                if len(source['question_numbers']) != row['questions']:
                    raise ValueError('candidate item count does not match selected anchor mode')
                if authored.get('options_each') is not None and source.get('features', {}).get('options_each') != authored['options_each']:
                    raise ValueError('candidate option count does not match selected anchor mode')
            if len(authored['author_answer_vector']) != authored['questions'] or authored['questions'] != row['questions']:
                raise ValueError('answer/item count differs')
            if len(re.findall(r'^\| \d+ \|', text, re.M)) != row['questions']:
                raise ValueError('per-item author evidence table incomplete')
            if passage_counts(text, row['passage_extraction']) != row['passage_token_counts']:
                raise ValueError('passage count not reproducible')
            if any(authored.get(f) is not False for f in ['independent_review', 'student_calibration', 'production_admission']):
                raise ValueError('author review promoted to external validation')
            if authored.get('all_responses_limit_words') == 1:
                if any(len(v.split()) != 1 for values in authored['author_answer_vector'] for v in values):
                    raise ValueError('one-word task contains multiword accepted response')
            for slot in authored.get('ungiven_oneword_slots', []):
                if any(len(v.split()) != 1 for v in authored['author_answer_vector'][slot - 1]):
                    raise ValueError('ungiven one-word slot has multiword response')
            for field in ['prior_draft_acquisition_id', 'actual_revision_audit_acquisition_id']:
                if authored.get(field) and authored[field] not in acquisitions:
                    raise ValueError('claimed revision evidence unregistered')
            coverage[row['grade']].add(row['core_kind'])
            questions += row['questions']
        except (KeyError, ValueError, IndexError, TypeError) as exc:
            errors.append(identity + ': ' + str(exc))
    for g in grades:
        if coverage[g] != {'reading', 'cloze', 'language'}:
            errors.append('missing grade core coverage: ' + str(g))
        if len(families[g]) < 2:
            errors.append('missing second paper family: ' + str(g))
    if questions != data.get('question_count'):
        errors.append('question total differs')
    for row in data.get('grades', []):
        try:
            file_ref(row['current_specification'])
            file_ref(row['comparison'])
        except (KeyError, ValueError) as exc:
            errors.append('grade review binding: ' + str(exc))
    if {r.get('grade') for r in data.get('grades', [])} != grades:
        errors.append('grade specification/comparison index incomplete')
    for risk in data.get('source_counterexamples', []):
        if risk.get('group_id') not in groups or risk.get('positive_answer_example') is not False:
            errors.append('counterexample silently admitted: ' + str(risk.get('id')))
    seed_private = None
    try:
        seed = json.loads(file_ref(data['seed_anchor_index']).read_text())
        if seed['group_count'] != 18 or seed['item_count'] != 162:
            raise ValueError('seed core set declaration changed')
        if len(seed['groups']) != seed['group_count']:
            raise ValueError('seed group count differs')
        seed_coverage = {g: set() for g in grades}
        for row in seed['groups']:
            group = groups[row['group_id']]
            if row['grade'] != group['grade'] or row['question_numbers'] != group['question_numbers'] or row['rationale_item_count'] != len(group['question_numbers']):
                raise ValueError('seed/source item relation differs')
            seed_coverage[row['grade']].add(row['core_kind'])
        if any(v != {'reading', 'cloze', 'language'} for v in seed_coverage.values()):
            raise ValueError('seed grade/core coverage incomplete')
        seed_private = acquisitions[seed['private_rationale_acquisition_id']]
        if seed_private['sha256'] != seed['private_rationale_sha256']:
            raise ValueError('seed private rationale digest binding differs')
        if check_cache:
            path = REPO / seed_private['path']
            if digest(path) != seed_private['sha256']:
                raise ValueError('seed private rationale file changed')
            private = json.loads(path.read_text())
            if private['group_count'] != seed['group_count'] or private['item_count'] != seed['item_count']:
                raise ValueError('private seed counts differ')
            for public, detail in zip(seed['groups'], private['groups']):
                items = detail['items']
                if public['group_id'] != detail['group_id'] or public['question_numbers'] != [x['source_number'] for x in items]:
                    raise ValueError('private seed item pairing differs')
                if any(not x.get('author_analysis') for x in items):
                    raise ValueError('seed item has no author rationale')
                if public['positive_answer_examples_excluded_source_numbers'] != [x['source_number'] for x in items if not x['positive_answer_example']]:
                    raise ValueError('seed risk not preserved in public index')
    except (KeyError, ValueError, IndexError, TypeError, OSError) as exc:
        errors.append('seed-anchor index: ' + str(exc))
    checked = 0
    if check_cache:
        ids = {groups[r['id']]['acquisition_id'] for r in expected_ids if r['id'] in groups}
        ids |= {v for row in candidates for v in json.loads((BASE / row['author_check']['path']).read_text()).values()
                if isinstance(v, str) and v in acquisitions}
        if seed_private:
            ids.add(seed_private['id'])
        for identity in sorted(ids):
            r = acquisitions[identity]
            if r.get('path'):
                p = REPO / r['path']
                if not p.is_file() or p.stat().st_size != r['bytes'] or digest(p) != r['sha256']:
                    errors.append('cached source/revision digest mismatch: ' + identity)
                checked += 1
    return dict(bindings_and_structure_valid=not errors, errors=errors, candidates_checked=len(candidates),
                questions_checked=questions, selected_source_groups=len(expected_ids),
                paper_families_by_grade={str(g): len(families[g]) for g in sorted(grades)},
                selected_source_and_revision_cache_files_checked=checked,
                independent_semantic_or_learner_validation=False,
                limitation='Structural completeness and digests cannot certify answer validity, difficulty, timing, rights or full benchmark completion.')



def check_request(request, index):
    errors = []
    groups = {g['id']: g for g in json.loads((BASE / 'FirstRelease/source-group-observations.json').read_text())['groups']}
    try:
        grade = request['grade']
        group = groups[request['anchor_group_id']]
        file_ref(request['specification'])
        current = next(g for g in index['grades'] if g['grade'] == grade)['current_specification']
        if request['specification'] != current or group['grade'] != grade:
            raise ValueError('wrong grade/current specification binding')
        if request['source_paper_acquisition_id'] != group['acquisition_id']:
            raise ValueError('wrong source paper family')
        fmt = request['format']
        if fmt['items'] != len(group['question_numbers']):
            raise ValueError('requested item count differs from complete anchor mode')
        if fmt.get('options_each') != group.get('features', {}).get('options_each'):
            raise ValueError('requested options differ from anchor mode')
        seed = json.loads(file_ref(index['seed_anchor_index']).read_text())
        ref = next(g for g in seed['groups'] if g['group_id'] == group['id'])
        if request['core_kind'] != ref['core_kind']:
            raise ValueError('requested core type differs from selected seed')
        positive = request.get('positive_source_answer_example_numbers', [])
        if not set(positive).issubset(group['question_numbers']) or set(positive) & set(ref['positive_answer_examples_excluded_source_numbers']):
            raise ValueError('missing or quarantined source answer used as positive exemplar')
        for field in ['source_text_copy_or_republication_admitted', 'commercial_model_training_admitted',
                      'third_party_source_text_transmission_admitted', 'independent_review',
                      'student_calibration', 'production_admission']:
            if request.get(field) is not False:
                raise ValueError('unsupported request admission: ' + field)
        if request['student_display'].get('independent_character_opening_story') is not False:
            raise ValueError('character story violates owner display scope')
    except (KeyError, ValueError, IndexError, StopIteration, TypeError) as exc:
        errors.append(str(exc))
    return dict(request_bindings_valid=not errors, errors=errors, model_called=False)


def self_check(data):
    cases = []
    for name, mutate in [
        ('wrong_grade', lambda x: x['candidates'][0].update(grade=12)),
        ('changed_candidate_digest', lambda x: x['candidates'][0]['candidate'].update(sha256='0' * 64)),
        ('wrong_anchor', lambda x: x['candidates'][0].update(anchor_group_ids=['g9.2026.cloze'])),
        ('missing_core_candidate', lambda x: x['candidates'].pop()),
        ('promoted_student_claim', lambda x: x.update(student_calibration=True)),
        ('promoted_source_counterexample', lambda x: x['source_counterexamples'][0].update(positive_answer_example=True)),
        ('changed_source_observation', lambda x: x['selected_source_groups'][0].update(canonical_sha256='0' * 64)),
        ('missing_seed_rationale_index', lambda x: x.pop('seed_anchor_index')),
    ]:
        altered = copy.deepcopy(data)
        mutate(altered)
        result = check(altered)
        cases.append(dict(case=name, rejected=not result['bindings_and_structure_valid'], errors=result['errors']))
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', type=Path, default=DEFAULT)
    parser.add_argument('--check-cache', action='store_true')
    parser.add_argument('--self-check', action='store_true')
    parser.add_argument('--request', type=Path, help='Validate an authoring request without calling a model')
    args = parser.parse_args()
    data = json.loads(args.index.read_text())
    result = check(data, args.check_cache)
    if args.self_check:
        result['synthetic_bookkeeping_rejections'] = self_check(data)
        result['self_check_passed'] = all(x['rejected'] for x in result['synthetic_bookkeeping_rejections'])
    if args.request:
        result['request_check'] = check_request(json.loads(args.request.read_text()), data)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if result['bindings_and_structure_valid'] and result.get('self_check_passed', True) and result.get('request_check', {}).get('request_bindings_valid', True) else 1


if __name__ == '__main__':
    raise SystemExit(main())
