"""An explicitly band-only task; never an inferred product-grade observation."""
import json
from grade_mode_evidence import load_ref


def validate_draft(d):
    assert d['band_reference_only'] is True and d['grade'] is None
    assert d['source_band'] == 'HK_KS1' and not d['mainland_grade_equivalence_established']
    assert d['family'] == 'listening_letter_completion'
    source = json.loads(load_ref(d['source_review']).read_text())['selected_band_only_tasks'][0]
    assert source['id'] == d['source_group_id'] and source['responses'] == 9
    assert source['individual_grade'] is None and not source['mainland_grade_equivalence_established']
    assert d['candidate_letters'] == source['candidate_letters'] == ['p', 'b']
    assert d['source_replay_rule'] == 'not_printed' and d['render_repeat_count'] == 1
    assert len(d['clips']) == 1 and set(d['speakers']) == {'M', 'W'}
    clip = d['clips'][0]
    assert clip['preview_seconds'] == clip['answer_seconds'] == 20
    assert set(t['speaker'] for t in clip['turns']) == {'M', 'W'}
    assert len(d['lists']) == 2 and [l['speaker'] for l in d['lists']] == ['M', 'W']
    assert all(len(l['items']) == 5 for l in d['lists'])
    assert [i.get('example', False) for l in d['lists'] for i in l['items']] == [True] + [False] * 9
    items = [i for l in d['lists'] for i in l['items'] if not i.get('example')]
    assert len(clip['questions']) == len(items) == 9
    assert [q['number'] for q in clip['questions']] == list(range(1,10))
    transcript = ' '.join(t['text'] for t in clip['turns']).lower()
    for q, i in zip(clip['questions'], items):
        assert not q['options'] and q['acceptedAnswers'] == [i['letter']]
        assert i['letter'] in d['candidate_letters'] and i['full_word'].startswith(i['letter'])
        assert i['stub'] == '_' + i['full_word'][1:] and i['full_word'].lower() in transcript
        assert q['rationale'] and i['number'] == q['number']
        assert q['owner'] in {l['name'] for l in d['lists']}
        owner = next(l for l in d['lists'] if i in l['items'])
        assert q['owner'] == owner['name'] and i['stub'] in q['stem']
        assert any(t['speaker']==owner['speaker'] and i['full_word'].lower() in t['text'].lower() for t in clip['turns'])
    return source
