"""Two-speaker matching: the classroom source supplies a script, not audio."""
def validate_draft(d):
    intention=d['family']=='listening_intention_classification'
    assert d['family'] in {'listening_intention_classification','listening_description_matching'}
    assert d['grade']=='advanced' and d['academic_shared_audio_matching']
    assert d['source_audio_status']=='explicitly_not_supplied_teacher_may_record_or_read_script'
    assert d['source_repeat_count'] is None and d['render_repeat_count']==1
    assert len(d['clips'])==1 and set(d['speakers'])=={'M','W'}
    clip=d['clips'][0];count=5 if intention else 4;labels=list('ABC' if intention else 'ABCDE')
    assert len(clip['questions'])==count and len(clip['turns'])>=8
    assert set(t['speaker'] for t in clip['turns'])=={'M','W'} and all(t['text'].strip() for t in clip['turns'])
    assert clip['preview_seconds']==clip['answer_seconds']==5*count
    assert [k for k,v in d['candidates']]==labels and len({v for k,v in d['candidates']})==len(labels)
    assert d['reuse_rule']==('explicit_more_than_once' if intention else 'not_printed')
    text=' '.join(t['text'] for t in clip['turns'])
    for q in clip['questions']:
        assert q['options']==d['candidates'] and q['answer'] in labels
        assert q['evidence_quote'] and q['evidence_quote'] in text
        assert set(q['candidate_reasons'])==set(labels) and all(q['candidate_reasons'].values())
    return True
