"""Complete two-choice extracts, four sentence gaps and five spatial labels."""
import re
COUNTS={'listening_multiselect':3,'listening_dialogue_choice':2,'listening_dialogue_sentence_completion':4,'listening_plan_label_matching':5,'listening_short_answer_pairs':6,'listening_note_table_completion':10,'listening_research_table_completion':5}
ROLES=['lower_left_room','inner_right_room','far_wall_shelves','upper_middle_room','right_annex']

def validate_draft(d):
    kind=d['family'];assert kind in COUNTS and d['grade']=='advanced' and d['academic_bundle_listening']
    assert d['source_repeat_count'] is None and d['render_repeat_count']==1
    assert len(d['clips'])==1 and d['fictional_illustrative_case']
    c=d['clips'][0];assert len(c['questions'])==COUNTS[kind]
    assert c['preview_seconds']==c['answer_seconds']==5*COUNTS[kind]
    assert all(t['text'].strip() for t in c['turns'])
    assert set(t['speaker']for t in c['turns'])==({'N'}if kind in {'listening_plan_label_matching','listening_short_answer_pairs','listening_note_table_completion','listening_research_table_completion'}else{'M','W'})
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
        if kind in {'listening_dialogue_sentence_completion','listening_short_answer_pairs','listening_note_table_completion','listening_research_table_completion'}:
            assert not q['options']
            if kind=='listening_dialogue_sentence_completion':assert q['stem'].count('____')==1
            assert q['acceptedAnswers'] and len({v.upper()for v in q['acceptedAnswers']})==len(q['acceptedAnswers'])
            assert all(1<=len(v.split())<=(1 if kind=='listening_research_table_completion'else 2 if kind=='listening_dialogue_sentence_completion'else 3) for v in q['acceptedAnswers'])
            if kind!='listening_note_table_completion' or n not in [4,6,9]:assert all(re.search(r'(?<![a-z])'+re.escape(fold(v))+r'(?![a-z])',fold(text)) for v in q['acceptedAnswers'])
            assert q['rejection_reasons'] and set(q['rejected'])==set(q['rejection_reasons'])
            assert not set(q['acceptedAnswers'])&set(q['rejected'])
            if kind!='listening_note_table_completion' or n!=9:
                assert all(re.fullmatch("[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*(?: [A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*)*",v)for v in q['acceptedAnswers']+q['rejected'])
        else:
            labels=list('ABCDEFGHI'if kind=='listening_plan_label_matching'else'ABCDEFGH'if kind=='listening_multiselect'else'ABC')
            assert [k for k,v in q['options']]==labels and q['answer']in labels
            assert set(q['candidate_reasons'])==set(labels) and all(q['candidate_reasons'].values())
            if kind=='listening_plan_label_matching':assert q['options']==d['candidates'] and q['answer']==d['answers_by_position'][n-1]
    assert offsets==sorted(offsets) and len(set(offsets))==len(offsets)
    if kind=='listening_short_answer_pairs':
        assert len(c['turns'])==1 and len(d['prompts'])==3 and d['printed_example']
        for n,prompt in enumerate(d['prompts']):
            qs=c['questions'][2*n:2*n+2];pair=qs[0]['fillPair']
            assert pair==qs[1]['fillPair'] and pair['positions']==[2*n+1,2*n+2]
            assert pair['order']=='either' and pair['distinctReferents'] and pair['localMatchingRule']=='distinct_known_referents_once'
            assert len(pair['members'])==2 and len({m['id']for m in pair['members']})==2
            forms=[v for m in pair['members']for v in m['forms']]
            assert len(set(v.lower()for v in forms))==len(forms) and all(q['acceptedAnswers']==forms for q in qs)
            assert prompt['stem'] in qs[0]['stem'] and prompt['stem'] in qs[1]['stem']
        assert d['printed_example'] in d['prompts'][1]['stem'] and all(d['printed_example'] not in q['acceptedAnswers'] for q in c['questions'][2:4])
    if kind=='listening_note_table_completion':
        assert len(c['turns'])==2 and d['subgroups']==[6,4]
        assert len(d['table_rows'])==3 and all(len(r)==5 for r in d['table_rows'])
        assert d['table_columns']==['Day','Time','Event','Venue','Ticket price']
        assert [[r,col]for r,row in enumerate(d['table_rows'])for col,value in enumerate(row)if '____'in value]==[[0,3],[1,2],[1,4],[2,2]]
        assert len(d['printed_facilities'])==6 and all(d['printed_facilities'])
        assert d['fixed_history'] and d['planning_decade'] and d['centre_name']
        assert 1800<=d['opening_year']<=2100 and 1<=d['open_days']<=366
        assert c['questions'][3]['acceptedAnswers']==[str(d['opening_year']),str(d['opening_year']//10*10)+'s','the '+str(d['opening_year']//10*10)+'s']
        assert c['questions'][5]['acceptedAnswers'][0]==str(d['open_days'])
        assert d['ticket_pence']>0 and c['questions'][8]['value_kind']=='sterling'
    if kind=='listening_multiselect':
        assert len(d['correct'])==3 and len(set(d['correct']))==3
        assert [k for k,v in d['candidates']]==list('ABCDEFGH') and len({v for k,v in d['candidates']})==8
        assert d['selection_order']=='either' and d['distinct_choices']
        for n,q in enumerate(c['questions']):
            assert q['options']==d['candidates'] and q['answer']==d['correct'][n]
            assert q['stem'].endswith(d['prompt'])
    if kind=='listening_research_table_completion':
        assert len(c['turns'])==1 and len(d['table_rows'])==3
        assert d['table_columns']==['Importance','Social and Environmental Factors','Other Factors','Personal Characteristics']
        assert all(len(r)==4 for r in d['table_rows'])
        assert [[r,col]for r,row in enumerate(d['table_rows'])for col,value in enumerate(row)if '____'in value]==[[0,3],[1,1],[1,2],[1,3],[2,1]]
        assert [int(re.search(r'(\d) ____',value)[1])for row in d['table_rows']for value in row if '____'in value]==list(range(1,6))
        assert d['fictional_data_not_causal_evidence'] and d['max_words']==1
    return True
