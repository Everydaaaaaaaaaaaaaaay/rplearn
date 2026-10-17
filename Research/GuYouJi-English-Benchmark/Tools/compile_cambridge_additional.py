"""Three complete historical reference forms, with separate answer contracts."""
import hashlib,json,re
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

CLAIMS='reading_writer_claims_tristate'
MATCH='paragraph_information_matching'
SHORT='bounded_extracted_short_answers'
LABELS={CLAIMS:['YES','NO','NOT GIVEN'],MATCH:list('ABCDEFGH')}
TITLES={CLAIMS:'作者观点三态判断',MATCH:'段落特定信息匹配',SHORT:'限词原文短答'}

def validate(d,s):
    kind=d['family'];assert kind in TITLES
    assert d['grade']==s['level']=='advanced' and kind==s['kind'] and d['source_group_id']==s['id']
    count={CLAIMS:4,MATCH:6,SHORT:3}[kind]
    assert len(d['items'])==s['responses']==count and d['fictional_illustrative_case']
    assert d['sections'] and all(v.strip() for v in d['sections'].values())
    if kind==MATCH:
        assert list(d['sections'])==s['features']['labels']==list('ABCDEFGH')
        assert d['reuse_rule']==s['features']['reuse_rule']=='explicit_more_than_once'
        assert 'You may use any letter more than once.' in d['instruction']
    if kind==CLAIMS:
        assert s['features']['labels']==LABELS[CLAIMS] and s['features']['writer_claims_not_external_truth']
    if kind==SHORT:
        assert list(d['sections'])==s['features']['labels']==list('ABCDEF')
        assert d['max_words']==s['features']['max_words']==3
        assert 'NO MORE THAN THREE WORDS' in d['instruction']
        assert [i['answer_section'] for i in d['items']]==['C','E','D']
        assert [i.get('list_members') is not None for i in d['items']]==[False,True,False]
    text='\n\n'.join(d['sections'].values())
    for item in d['items']:
        assert item['stem'] and item['rationale']
        if kind in LABELS:
            assert item['answer'] in LABELS[kind]
            assert set(item['candidate_reasons'])==set(LABELS[kind]) and all(item['candidate_reasons'].values())
            if kind==CLAIMS and item['answer']=='NOT GIVEN':
                assert not item['evidence_quote'] and item['unreported_dimension']
                assert item['all_sections_checked']==list(d['sections'])
            else:
                scope=d['sections'][item['answer']] if kind==MATCH else text
                assert item['evidence_quote'] and item['evidence_quote'] in scope
            if kind==MATCH:assert len([v for v in item['candidate_reasons'].values() if v.startswith('符合：')])==1
        else:
            assert item['accepted'] and item['evidence_quote'] in d['sections'][item['answer_section']]
            assert all(1<=len(v.split())<=3 for v in item['accepted'])
            assert item['rejected'] and set(item['rejected'])==set(item['rejection_reasons'])
            assert not set(item['accepted']) & set(item['rejected'])
            if item.get('list_members'):
                assert len(item['list_members'])==len(set(item['list_members']))==3
                assert item['accepted']==[' '.join(item['list_members'])]
                assert all(re.search(r'\b'+re.escape(v)+r'\b',item['evidence_quote']) for v in item['list_members'])
            else:
                assert all(v in item['evidence_quote'] for v in item['accepted'])
    return True

def compile_author(manuscript,version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings'] if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups'] if s['id']==d['source_group_id']);validate(d,s)
    kind=d['family'];body='### '+d['passage_title']+'\n\n'+'\n\n'.join(('### '+k+'\n\n' if kind!=CLAIMS else '')+v for k,v in d['sections'].items());qs=[]
    for n,i in enumerate(d['items'],1):
        if kind in LABELS:
            options=[[k,k if kind==MATCH else {'YES':'与作者主张一致','NO':'与作者主张矛盾','NOT GIVEN':'无法从全文确定作者对此的看法'}[k]] for k in LABELS[kind]]
            q=dict(number=n,stem=i['stem'],options=options,answer=i['answer'],rationale=i['rationale']+'；'+'；'.join(k+'：'+v for k,v in i['candidate_reasons'].items()))
        else:
            contract=dict(version=1,review='author_context_checked',normalization='source_list_v1' if i.get('list_members') else 'source_excerpt_v1',sourceBound=True,unknownSyntax='review',hyphenatedWordCount='one',maxWords=3,unlisted='review',rejectedAnswers=i['rejected'])
            if i.get('list_members'):contract.update(listSize=3,listOrder='any',listMembersDistinct=True)
            q=dict(number=n,stem=i['stem'],options=[],answer=' / '.join(i['accepted']),acceptedAnswers=i['accepted'],fillMarking=contract,rationale=i['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in i['rejection_reasons'].items()))
        qs.append(q)
    block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists() and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version=version,id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,cambridge_additional_academic=True,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),stem_English_words=sum(words(q['stem']) for q in qs),options_English_words_with_repeated_bank=sum(words(v) for q in qs for k,v in q['options']),output_response_positions=len(qs)),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    m=dict(id=d['id'],grade='advanced',family=kind,family_label=TITLES[kind],title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary={CLAIMS:'1全文 / 4陈述 / YES、NO、NOT GIVEN / 作者主张边界',MATCH:'1全文8段A—H / 6特定信息 / 段落字母可复用',SHORT:'1全文6段A—F / 3问题 / 每答最多三词 / 第二答含三成员仍为一题'}[kind])
    if kind==MATCH:m['use_select_controls']=True
    return m

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s)
    assert g['questions']==a['review_response_tasks'] and s['source_full_input_verified'] and not s['source_original_key_is_gold']
    texts=[load_ref(r).read_text() for r in s['source_pages']]
    if d['family']==CLAIMS:
        assert all(v in texts[-1] for v in ['YES','NO','NOT GIVEN','4 Thirty'])
        assert s['original_question_numbers']==[4,5,6,7] and s['key_local_numbers']==[1,2,3,4]
    elif d['family']==MATCH:
        assert 'You may use any letter more than once.' in texts[-1] and g['fixedSharedBank']
        assert s['reference_keys']==list('CFEHAD')
    else:
        assert 'NO MORE THAN THREE WORDS' in texts[1] and s['features']['whole_task_source_order']==['C','E','D']
        assert g['questions'][1]['fillMarking']['normalization']=='source_list_v1'
    return True
