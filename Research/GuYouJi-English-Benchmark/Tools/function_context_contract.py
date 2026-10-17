"""Keep a complete, independently answered context section bound to its source."""
def check(group, audit, binding, source):
    features = source['features']
    assert source['kind'] == binding['family'] == group['kind'] == 'function_choice'
    assert source['level'] == binding['level'] == group['grade'] == 'primary6'
    assert features == binding['source_features'] == {
        'Chinese_function_contexts': 10, 'responses': 10,
        'options_each': 3, 'shared_bank': False, 'passages': 0,
        'necessary_images': False, 'necessary_audio': False,
    }
    assert source['complete_selected_group_reviewed']
    assert source['input_layer'] == 'public_reader_text'
    assert not source['school_exam_authentication']
    assert source['source_original_key_not_gold']
    assert len(group['questions']) == audit['questions'] == binding['responses'] == 10
    assert not group.get('requiredAudioAssets') and not group.get('requiredPassageImages')
    assert not group.get('fixedSharedBank')
    assert audit['Chinese_contexts'] == 10 and audit['roles_and_communicative_goals_explicit']
    assert audit['no_necessary_image_or_audio']
    assert audit['student_passage'] == ''
    assert audit['source_key_not_copied']
    assert [q['number'] for q in group['questions']] == list(range(1, 11))
    assert len(audit['candidate_reason_rows']) == 10
    for q, reason in zip(group['questions'], audit['candidate_reason_rows']):
        assert len(q['options']) == 3
        assert [label for label, _ in q['options']] == list('ABC')
        assert isinstance(q['answer'], str) and q['answer'] in {'A', 'B', 'C'}
        assert len({text for _, text in q['options']}) == 3
        assert reason['number'] == q['number']
        assert set(reason['grounds']) == set('ABC')
        assert all(reason['grounds'].values())
        assert reason['key'] == q['answer']
        assert all(reason['grounds'][label] in q['rationale'] for label in 'ABC')
    assert audit['author_answer_vector'] == [q['answer'] for q in group['questions']]
    return True
