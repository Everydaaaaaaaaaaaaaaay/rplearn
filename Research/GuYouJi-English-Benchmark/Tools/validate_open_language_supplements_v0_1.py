#!/usr/bin/env python3
"""Check supplemental source/candidate bindings and response contracts, not semantics."""
import argparse
import json
import re
import validate_firstrelease_v0_3 as core
import validate_firstrelease_v0_7 as roles


def check(index):
    errors = []
    total = 0
    for row in index['candidates']:
        try:
            text = core.file_ref(row['candidate']).read_text()
            authored = json.loads(core.file_ref(row['author_check']).read_text())
            source = json.loads(core.file_ref(row['supplemental_reference']).read_text())
            core.file_ref(row['specification_at_authoring'])
            if not source.get('complete_selected_group_reviewed'):
                raise ValueError('supplemental selected group incomplete')
            if source.get('source_key_status') != 'same_file_published_simulated_reference_not_exhaustive_not_independent_gold':
                raise ValueError('source-key role changed; re-review required')
            if source['grade'] != authored['grade'] or source['group_id'] != authored['anchor_group_ids'][0]:
                raise ValueError('source grade or group identity differs')
            if source['given_prompt_count'] != len(authored['given_slots']) or source['ungiven_prompt_count'] != len(authored['ungiven_oneword_slots']):
                raise ValueError('given/ungiven form does not match selected supplemental mode')
            if source['all_responses_limit_words'] != authored['all_responses_limit_words']:
                raise ValueError('source and candidate response limits differ')
            for name, field in [('candidate', 'candidate'), ('specification_at_authoring', 'specification')]:
                if authored[field + '_path'] != row[name]['path'] or authored[field + '_sha256'] != row[name]['sha256']:
                    raise ValueError('author check does not bind actual artifact')
            blocks = re.findall(r'<!-- passage:start -->\n(.*?)\n<!-- passage:end -->', text, re.S)
            if len(blocks) != 1:
                raise ValueError('single complete passage required')
            gaps = re.findall(r'\((\d+)\) _+(?: \(([A-Za-z]+)\))?', blocks[0])
            if [int(n) for n, _ in gaps] != list(range(1, authored['questions'] + 1)):
                raise ValueError('missing/repeated/out-of-order blanks')
            if [int(n) for n, root in gaps if root] != authored['given_slots']:
                raise ValueError('actual given-root positions differ')
            if [int(n) for n, root in gaps if not root] != authored['ungiven_oneword_slots']:
                raise ValueError('actual ungiven positions differ')
            if len(authored['author_answer_vector']) != authored['questions'] or roles.author_evidence_count(text) != authored['questions']:
                raise ValueError('answers or real author evidence incomplete')
            if authored['all_responses_limit_words'] == 1 and any(len(a.split()) != 1 for answers in authored['author_answer_vector'] for a in answers):
                raise ValueError('one-word form contains multiword answer')
            if core.passage_counts(text, 'explicit_passage_markers') != row['passage_token_counts']:
                raise ValueError('passage token counts differ')
            for key in ['independent_review', 'student_calibration', 'production_admission', 'commercial_admission']:
                if authored.get(key) is not False or index.get(key) is not False:
                    raise ValueError('unsupported validation/admission claim: ' + key)
            if row['included_in_core_frozen_counts'] is not False:
                raise ValueError('supplement incorrectly included in core count')
            total += authored['questions']
        except (KeyError, ValueError, OSError) as exc:
            errors.append(row.get('id', '?') + ': ' + str(exc))
    if len(index['candidates']) != index['candidate_count'] or total != index['question_count']:
        errors.append('supplemental counts differ')
    return {'bindings_and_structure_valid': not errors, 'errors': errors,
            'supplemental_candidates': len(index['candidates']), 'supplemental_responses': total,
            'core_counts_changed': False, 'independent_semantic_or_learner_validation': False,
            'limitation': 'Form and digest checks do not certify semantic validity, grade difficulty, source authenticity, rights or production scoring.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index', default=str(core.BASE / 'FirstRelease/open-language-supplement-candidates-v0.1.json'))
    args = parser.parse_args()
    result = check(json.loads(open(args.index).read()))
    print(json.dumps(result, ensure_ascii=False, indent=2))
    raise SystemExit(0 if result['bindings_and_structure_valid'] else 1)
