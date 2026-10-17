"""Check a source-bounded whole five-triplet classification section."""


def check(group, audit, binding, source):
    assert group['kind'] == binding['family'] == source['kind'] == 'word_category_choice'
    assert group['grade'] == binding['level'] == source['level'] == 'primary6'
    assert source['features'] == binding['source_features'] == {
        'word_triplets': 5, 'responses': 5, 'options_each': 3,
        'shared_bank': False, 'passages': 0,
        'necessary_images': False, 'necessary_audio': False,
    }
    assert source['complete_selected_group_reviewed'] and source['source_original_key_not_gold']
    assert source['source_physical_pages'] == [2]
    assert source['input_layer'] == 'actual_public_native_preview_and_separate_reader_key'
    assert not source['school_exam_authentication']
    assert len(group['questions']) == audit['questions'] == binding['responses'] == 5
    assert not group.get('requiredPassageImages') and not group.get('requiredAudioAssets')
    assert not group.get('fixedSharedBank')
    assert audit['source_key_not_copied'] and audit['no_necessary_image_or_audio']
    assert audit['category_criteria'] == [
        'comparative_forms_vs_occupation_noun', 'past_forms_vs_noun',
        'objects_vs_places', 'time_words_vs_comparative', 'past_forms_vs_base_verb',
    ]
    assert len(audit['candidate_reason_rows']) == 5
    assert [q['number'] for q in group['questions']] == list(range(1, 6))
    for q, row in zip(group['questions'], audit['candidate_reason_rows']):
        assert [k for k, _ in q['options']] == list('ABC')
        assert len({text for _, text in q['options']}) == 3
        assert all(len(text.split()) == 1 for _, text in q['options'])
        assert isinstance(q['answer'], str) and q['answer'] in {'A', 'B', 'C'}
        assert row['number'] == q['number'] and row['key'] == q['answer']
        assert set(row['grounds']) == set('ABC')
        assert all(ground and ground in q['rationale'] for ground in row['grounds'].values())
    assert audit['author_answer_vector'] == [q['answer'] for q in group['questions']]
    return True
