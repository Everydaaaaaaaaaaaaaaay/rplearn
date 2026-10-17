"""Complete two-choice extracts, four sentence gaps and five spatial labels."""
import re
COUNTS={'listening_dialogue_choice':2,'listening_dialogue_sentence_completion':4,'listening_plan_label_matching':5}
ROLES=['lower_left_room','inner_right_room','far_wall_shelves','upper_middle_room','right_annex']

def validate_draft(d):
    kind=d['family'];assert kind in COUNTS and d['grade']=='advanced' and d['academic_bundle_listening']
    assert d['source_repeat_count'] is None and d['render_repeat_count']==1
    assert len(d['clips'])==1 and d['fictional_illustrative_case']
    c=d['clips'][0];assert len(c['questions'])==COUNTS[kind]
    assert c['preview_seconds']==c['answer_seconds']==5*COUNTS[kind]
    assert all(t['text'].strip() for t in c['turns'])
    assert set(t['speaker']for t in c['turns'])==({'N'}if kind=='listening_plan_label_matching'else{'M','W'})
    text=' '.join(t['text']for t in c['turns']);fold=lambda v:re.sub(r'[-‐‑–]',' ',v).lower()
    if kind=='listening_plan_label_matching':
        assert len(c['turns'])==1 and d['plan_roles']==ROLES
        assert [k for k,v in d['candidates']]==list('ABCDEFGHI') and len({v for k,v in d['candidates']})==9
        assert len(d['fixed_labels'])==6 and all(d['fixed_labels'].values())
        assert d['reuse_rule']=='not_printed' and len(set(d['answers_by_position']))==5
    offsets=[]
    for n,q in enumerate(c['questions'],1):
        assert q['evidence_quote'] and q['evidence_quote']in text and q['rationale']
        offsets.append(text.index(q['evidence_quote']))
        if kind=='listening_dialogue_sentence_completion':
            assert q['stem'].count('____')==1 and not q['options']
            assert q['acceptedAnswers'] and len({v.upper()for v in q['acceptedAnswers']})==len(q['acceptedAnswers'])
            assert all(1<=len(v.split())<=2 for v in q['acceptedAnswers'])
            assert all(re.search(r'(?<![a-z])'+re.escape(fold(v))+r'(?![a-z])',fold(text)) for v in q['acceptedAnswers'])
            assert q['rejection_reasons'] and set(q['rejected'])==set(q['rejection_reasons'])
            assert not set(q['acceptedAnswers'])&set(q['rejected'])
        else:
            labels=list('ABCDEFGHI'if kind=='listening_plan_label_matching'else'ABC')
            assert [k for k,v in q['options']]==labels and q['answer']in labels
            assert set(q['candidate_reasons'])==set(labels) and all(q['candidate_reasons'].values())
            if kind=='listening_plan_label_matching':assert q['options']==d['candidates'] and q['answer']==d['answers_by_position'][n-1]
    assert offsets==sorted(offsets) and len(set(offsets))==len(offsets)
    return True
