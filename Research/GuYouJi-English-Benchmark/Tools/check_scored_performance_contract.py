#!/usr/bin/env python3
"""Original structural examples and failures; no invented source assessments."""
import copy
import json
import sys

sys.dont_write_bytecode = True
from validate_scored_performances import BASE, inspect_performance


def main():
    fixtures = {p.stem: json.loads(p.read_text()) for p in
                (BASE / 'Performances/Fixtures').glob('*.json')}
    for name, record in fixtures.items():
        assert inspect_performance(record, {}, {})['structure_valid'], name
    cases = []

    def reject(name, mutate, fixture='task-total-only'):
        record = copy.deepcopy(fixtures[fixture])
        mutate(record)
        result = inspect_performance(record, {}, {})
        assert not result['structure_valid'], name
        assert result['gold_admission'] is False and result['production_admission'] is False
        cases.append(name)

    reject('production_admission', lambda r: r.update(admission='production'))
    reject('missing_task_total', lambda r: r.update(scores=[]))
    reject('overall_as_task', lambda r: r['scores'][0].update(scope='overall'))
    reject('section_as_task', lambda r: r['scores'][0].update(scope='section'))
    reject('total_names_dimension', lambda r: r['scores'][0].update(criterion_id='content'))
    reject('unpublished_dimension_score', lambda r: r['criteria'][0].update(score_id='task.total'))
    reject('declared_dimension_references_total', lambda r: r['criteria'][0].update(status='published',score_id='task.total'))
    reject('unknown_dimension', lambda r: r['scores'][0].update(scope='criterion',criterion_id='absent'))
    reject('duplicate_scope', lambda r: r['scores'].append({**r['scores'][0],'id':'task.other'}))
    reject('duplicate_reference_id', lambda r: r['references'].append(copy.deepcopy(r['references'][0])))
    reject('duplicate_scale_id', lambda r: r['scales'].append(copy.deepcopy(r['scales'][0])))
    reject('duplicate_criterion_id', lambda r: r['criteria'].append(copy.deepcopy(r['criteria'][0])))
    reject('outside_band', lambda r: r['scores'][0].update(value=10))
    reject('wrong_half_step', lambda r: r['scores'][0].update(value=6.25))
    reject('score_nan', lambda r: r['scores'][0].update(value=float('nan')))
    reject('score_infinity', lambda r: r['scores'][0].update(value=float('inf')))
    reject('scale_nan', lambda r: r['scales'][0].update(minimum=float('nan')))
    reject('step_infinity', lambda r: r['scales'][0].update(increment=float('inf')))
    reject('empty_scale', lambda r: r['scales'][0].update(maximum=0))
    reject('unknown_score_scale', lambda r: r['scores'][0].update(scale_id='absent'))
    reject('fake_source_score_from_fixture', lambda r: r['scores'][0].update(score_origin='published_source'))
    reject('wrong_score_evidence_role', lambda r: r['scores'][0].update(evidence_ref_ids=['response']))
    reject('missing_prompt_claimed_paired', lambda r: r['prompt'].update(status='paired'), 'prompt-not-acquired')
    reject('unresolved_visual_as_paired', lambda r: r['prompt'].update(visual_dependency_status='unknown'))
    reject('acquired_visual_without_asset', lambda r: r['prompt'].update(visual_dependency_status='acquired'))
    reject('response_used_as_prompt', lambda r: r['prompt'].update(text_ref_ids=['response']))
    reject('prompt_used_as_response', lambda r: r['response'].update(ref_ids=['prompt']))
    reject('corrected_source_errors', lambda r: r['response'].update(errors_preserved=False))
    reject('audio_as_written_response', lambda r: r['references'][1].update(representation='audio'))
    reject('unverified_full_transcription', lambda r: r['references'][1].update(transcription_status='unverified'))
    reject('unknown_rubric_has_version', lambda r: r['rubric'].update(scoring_version='invented'))
    reject('historical_match_without_rubric', lambda r: r['rubric'].update(historical_match_status='source_established'))
    reject('known_scale_lacks_version', lambda r: r['scales'][0].update(version=None))
    reject('invented_independent_review', lambda r: r['review'].update(independent='documented'))
    reject('invented_learner_calibration', lambda r: r['review'].update(learner_calibration='documented'))
    reject('source_score_used_as_review', lambda r: r['review'].update(independent='documented',independent_evidence_ref_ids=['score']))
    reject('invented_permission', lambda r: r['rights'].update(status='documented_scope'))
    reject('score_used_as_permission', lambda r: r['rights'].update(status='documented_scope',scope_evidence_ref_ids=['score']))
    reject('copyright_text_inline', lambda r: r.update(full_source_response='Should stay in private source/cache'))
    print(json.dumps(dict(original_positive_fixtures=len(fixtures),negative_rejections=len(cases),
        cases=cases,gold_admission=False,production_admission=False,
        limitation='Structural synthetic cases;not scoring accuracy or publication permission'),indent=2))


if __name__ == '__main__':
    main()
