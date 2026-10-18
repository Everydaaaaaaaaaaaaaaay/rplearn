"""Source-bound five-pool word-order groups with bounded, non-exhaustive keys."""
import hashlib
import json
import re
from collections import Counter
from math import prod
from grade_mode_evidence import load_ref
from compile_primary6_written_groups import ref, words
from quality_review_contract import response_markdown


def tokens(text):
    return re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)*", text)


def validate(d,s):
    assert d['grade'] == s['level'] == 'primary6' and d['family'] == s['kind'] == 'word_order_sentence'
    assert d['source_group_id'] == s['id'] and s['responses'] == 5 and s['source_full_input_verified']
    assert s['source_key_acquired'] is s['school_exam_authentication'] is False
    assert s['features'] == dict(sentence_tasks=5,responses=5,word_pools=5,printed_token_counts=[13,11,7,8,8],case_and_punctuation_required=True,max_words_each=None)
    assert len(d['items']) == 5
    for i,r in enumerate(d['items']):
        assert len(r['pool']) == [13,11,7,8,8][i]
        assert all(re.fullmatch(r"(?:[a-z]+(?:'[a-z]+)*|I)",v) for v in r['pool'])
        assert r['accepted'] and len(r['accepted']) == len(set(r['accepted'])) and r['reason']
        assert r['ending'] == ('?' if i==4 else '.')
        pool = Counter(v.lower() for v in r['pool'])
        assert r['pool'] != [t if t=='I' else t.lower() for t in tokens(r['accepted'][0])], 'Print a scrambled pool, not the reference order'
        for sentence in r['accepted']:
            assert re.fullmatch(r"[A-Z][A-Za-z']*(?:(?: |, )[A-Za-z]+(?:'[A-Za-z]+)*)*[.?]",sentence)
            assert sentence[-1] == r['ending'] and Counter(v.lower() for v in tokens(sentence)) == pool
            for n,t in enumerate(tokens(sentence)):
                expected = 'I' if t.lower()=='i' else t.lower()
                assert t == (expected[0].upper()+expected[1:] if n==0 else expected)
    return True


def compile_author(manuscript):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings'])
    b=next(v for v in json.loads(bp.read_text())['bindings'] if v['id']==d['source_binding'])
    s=next(v for v in json.loads(load_ref(b['source_index']).read_text())['groups'] if v['id']==b['source_group_id'])
    validate(d,s)
    tasks=[]
    for n,r in enumerate(d['items'],1):
        tasks.append(dict(number=n,stem='词池：'+' / '.join(r['pool']),options=[],wordPool=r['pool'],
            wordOrder=dict(version=1,id=d['id'],positions=[1,2,3,4,5]),acceptedAnswers=r['accepted'],
            fillMarking=dict(version=1,review='author_context_checked',normalization='whole_sentence_tokens_v1',
                useAllTokens='exact_multiset',caseRule='sentence_initial_and_printed_tokens',endings=[r['ending']],
                maxWords=None,unlisted='review',unknownSyntax='review',rejectedAnswers=[]),
            rationale=r['reason']+'；全部给词必须使用，重复项按出现次数使用，不增删或变形。已列语序同等接受；其他排列待复核，不据一个参考句排除。'))
    block=response_markdown(tasks)
    p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json')
    teacher='\n\n'.join('### '+str(q['number'])+'\n\n'+q['rationale']+'\n\n'+'\n\n'.join(q['acceptedAnswers']) for q in tasks)
    text='# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n\n'+d['source_notice']+'\n'
    if p.exists():assert p.read_text()==text
    else:p.write_text(text)
    a=dict(version='0.1',id=d['id'],grade=d['grade'],questions=5,candidate_sha256=ref(p)['sha256'],
        source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),word_order_five=True,
        review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),
        student_passage='',fully_filled_sentences=[r['accepted'][0] for r in d['items']],
        full_slot_substitutions=[dict(number=n,accepted_full_inputs=r['accepted']) for n,r in enumerate(d['items'],1)],
        independent_word_pools=True,full_fill_variant_combinations=prod(len(r['accepted']) for r in d['items']),
        cartesian_payload_not_duplicated=True,source_count_increment=0,authored_student_inputs_complete=True,
        independent_teacher_student_commercial_production_validated=False,
        load_measure=dict(body_English_words=0,stem_English_words=sum(words(q['stem']) for q in tasks),
            options_English_words_with_repeated_bank=0,output_response_positions=5,
            printed_pool_tokens_each=[len(r['pool']) for r in d['items']],
            output_known_sentence_tokens_each=[[len(tokens(v)) for v in r['accepted']] for r in d['items']]))
    text=json.dumps(a,ensure_ascii=False,indent=2)+'\n'
    if ap.exists():assert ap.read_text()==text
    else:ap.write_text(text)
    return dict(id=d['id'],grade='primary6',family=d['family'],family_label='给词组句',title=d['title'],questions=5,
        candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],
        format_summary='5独立词池 / 13、11、7、8、8词 / 全词原样使用 / 调整句首大小写和标点 / 第5题问句 / 多合法语序并列接受')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s)
    selected=json.loads(load_ref(s['selected_native']).read_text());native=json.loads(load_ref(selected['native_text']).read_text())
    assert selected['configuration']==b['source_features']==s['features'] and selected['source']==s['source']
    assert '注意大小写和标点符号' in selected['spans'][0]['text']
    printed_rows=re.findall(r'（[1-5]）([^\n]+)','\n'.join(span['text'] for span in selected['spans']))
    assert [len(tokens(row)) for row in printed_rows]==s['features']['printed_token_counts']
    for span in selected['spans']:
        text=native['pages'][span['physical_page']-1]['text'][span['start']:span['end']]
        assert text==span['text'] and hashlib.sha256(text.encode()).hexdigest()==span['sha256']
    assert a['word_order_five'] and b['options_each']==0 and b['responses']==len(g['questions'])==5
    for q,r in zip(g['questions'],d['items']):
        assert q['stem']=='词池：'+' / '.join(r['pool']) and q['wordPool']==r['pool']
        assert q['acceptedAnswers']==r['accepted'] and q['options']==[]
        assert q['wordOrder']==dict(version=1,id=d['id'],positions=[1,2,3,4,5])
        assert q['fillMarking']==dict(version=1,review='author_context_checked',normalization='whole_sentence_tokens_v1',
            useAllTokens='exact_multiset',caseRule='sentence_initial_and_printed_tokens',endings=[r['ending']],maxWords=None,
            unlisted='review',unknownSyntax='review',rejectedAnswers=[])
    assert a['full_slot_substitutions']==[dict(number=n,accepted_full_inputs=r['accepted']) for n,r in enumerate(d['items'],1)]
    assert a['full_fill_variant_combinations']==prod(len(r['accepted']) for r in d['items']) and a['independent_word_pools']
    return True
