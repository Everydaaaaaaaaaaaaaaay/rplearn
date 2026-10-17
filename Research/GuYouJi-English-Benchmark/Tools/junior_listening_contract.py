"""Specific observed junior configurations, separate from any year-wide rules."""
CONFIGS = {
 'grade8-xiaoshan2025-21cnjy22251031.listening.sectionA': (8, 'listening_short_conversation_choice', [1,1,1,1,1], ['MW']*5, 1, 1),
 'grade8-xiaoshan2025-21cnjy22251031.listening.sectionB': (8, 'listening_long_conversation_choice', [2,3], ['MW']*2, 2, 1.5),
 'grade8-xiaoshan2025-21cnjy22251031.listening.sectionC': (8, 'listening_passage_choice', [5], ['N'], 2, 1.5),
 'zz.g9.25123674.listening.sectionA': (9, 'listening_short_conversation_choice', [1,1,1,1,1], ['MW']*5, 2, 1),
 'zz.g9.25123674.listening.sectionB': (9, 'listening_multi_question_choice', [2,2,3,3], ['MW','MW','N','MW'], 2, 1),
 'zz.g9.25123674.listening.sectionC': (9, 'listening_table_completion', [5], ['N'], 2, 1),
}


def validate_draft(draft):
    grade, family, counts, roles, repeats, points = CONFIGS[draft['source_group_id']]
    assert draft['junior_source_bound'] and draft['grade'] == grade and draft['family'] == family
    assert draft['source_repeat_count'] == repeats
    assert [len(c['questions']) for c in draft['clips']] == counts
    for clip, count, role in zip(draft['clips'], counts, roles):
        assert set(t['speaker'] for t in clip['turns']) == set(role)
        assert all(t['text'].strip() for t in clip['turns'])
        preview, answer = (0, 10) if grade == 8 and family == 'listening_short_conversation_choice' else (5*count, 5*count)
        assert (clip['preview_seconds'], clip['answer_seconds']) == (preview, answer)
        for q in clip['questions']:
            if family == 'listening_table_completion':
                assert not q['options'] and q['acceptedAnswers'] and q['fillMarking']
                assert q['fillMarking']['maxWords']==1 and q['fillMarking']['unlisted']=='review'
            else:
                assert [k for k, _ in q['options']] == ['A','B','C'] and q['answer'] in 'ABC'
                assert all(k+'：' in q['rationale'] for k in 'ABC')
    return grade, family, counts, roles, repeats, points
