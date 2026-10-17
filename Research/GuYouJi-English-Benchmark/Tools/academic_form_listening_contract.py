"""One whole eight-response shipping form, including the necessary 3-D box."""
import re

def validate_draft(d):
    assert d['family']=='listening_form_completion' and d['grade']=='advanced' and d['academic_form_listening']
    assert d['fictional_illustrative_case'] and d['source_repeat_count'] is None and d['render_repeat_count']==1
    assert len(d['clips'])==1 and len(d['clips'][0]['questions'])==8
    c=d['clips'][0];assert c['preview_seconds']==c['answer_seconds']==40
    assert set(t['speaker']for t in c['turns'])=={'M','W'}
    assert len(d['form'])==8 and all(d['form'].values())
    assert set(d['dimensions'])=={'length_metres','width_mm','height_mm'}
    assert 0<d['dimensions']['height_mm']<d['dimensions']['width_mm']<1000
    assert d['total_pence']>0 and d['total_pence']%100==0
    qs=c['questions'];text=' '.join(t['text']for t in c['turns']);offsets=[]
    for n,q in enumerate(qs,1):
        assert not q['options'] and q['acceptedAnswers'] and q['rationale']
        assert q['evidence_quote'] in text;offsets.append(text.index(q['evidence_quote']))
        assert q['rejection_reasons'] and set(q['rejected'])==set(q['rejection_reasons']) and not set(q['acceptedAnswers'])&set(q['rejected'])
        if n not in [3,4,5,8]:
            assert all(v.lower() in text.lower() for v in q['acceptedAnswers'])
            assert all(len(v.split())<=3 for v in q['acceptedAnswers'])
    assert offsets==sorted(offsets) and len(set(offsets))==8
    assert qs[2]['acceptedAnswers']==[d['form']['postcode']] and re.fullmatch('[A-Z]{1,2}[0-9][A-Z0-9]? [0-9][A-Z]{2}',d['form']['postcode'])
    pair=qs[5]['fillPair'];assert pair==qs[6]['fillPair'] and pair['positions']==[6,7]
    assert pair['order']=='either' and pair['distinctReferents'] and pair['localMatchingRule']=='distinct_known_referents_once'
    assert len(pair['members'])==2 and len({m['id']for m in pair['members']})==2
    forms=[v for m in pair['members']for v in m['forms']];assert len(set(v.lower()for v in forms))==len(forms)
    assert qs[5]['acceptedAnswers']==qs[6]['acceptedAnswers']==forms and all('clothes' not in m['forms']for m in pair['members'])
    assert qs[0]['acceptedAnswers']==[d['form']['surname']] and qs[1]['acceptedAnswers']==[d['form']['college_name']]
    return True
