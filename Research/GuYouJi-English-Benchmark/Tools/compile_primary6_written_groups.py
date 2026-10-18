"""Five given-form sentences and a five-gap mixed-clause dialogue.

These contracts preserve the printed source configuration without inheriting
its missing key, spelling defects, or inferred restrictions on reuse.
"""
import hashlib
import json
import re
from itertools import product
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown


def ref(path):
    path = path.resolve()
    return dict(path=str(path.relative_to(BASE) if path.is_relative_to(BASE) else path.relative_to(REPO)),
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def validate(d, s):
    assert d['grade'] == s['level'] == 'primary6'
    assert d['source_group_id'] == s['id'] and d['family'] == s['kind']
    assert s['responses'] == 5 and s['source_full_input_verified']
    assert s['source_key_acquired'] is False and s['school_exam_authentication'] is False
    if d['mode'] == 'given_forms5':
        assert s['features'] == dict(sentence_tasks=5, responses=5, given_positions=[1,2,3,4,5],
            source_max_words_each=None, maximum_one_word_explicitly_rejected=True)
        assert len(d['sentences']) == 5
        for r in d['sentences']:
            assert r['frame'].count('____') == 1 and re.fullmatch('[a-z]+', r['lemma'])
            assert r['accepted'] and len(r['accepted']) == len(set(r['accepted']))
            assert set(r['grounds']) == set(r['accepted'])
            assert r['rejected'] and all(r['rejected'].values())
            assert not set(r['accepted']) & set(r['rejected'])
        evidence = json.loads(load_ref(d['variant_evidence']).read_text())
        for r in d['sentences']:
            if r['lemma'] in evidence['forms']:
                assert set(evidence['forms'][r['lemma']]) <= set(r['accepted'])
    else:
        assert d['mode'] == 'dialogue_clauses5'
        assert s['features'] == dict(dialogues=1, speakers=2, responses=5, shared_candidates=5,
            complete_question_candidate_count=2, conjunction_initial_clause_candidate_count=3,
            printed_frame_period_before_slots=[2,4], printed_frame_comma_before_slots=[5], reuse_rule='not_explicit')
        assert re.findall(r'\((\d+)\) ____', d['passage']) == list('12345')
        assert len(d['passage'].split('\n\n')) == 7
        assert [k for k,v in d['shared_candidates']] == list('ABCDE')
        candidates = dict(d['shared_candidates'])
        assert len(set(candidates.values())) == 5
        assert sum(v.endswith('?') for v in candidates.values()) == 2
        assert sum(v.startswith(('And ', 'but ')) for v in candidates.values()) == 3
        assert '. (2) ____' in d['passage'] and '. (4) ____' in d['passage'] and ', (5) ____' in d['passage']
        assert len(d['slots']) == 5
        assert '未规定每项只用一次' in d['instruction']
        assert not any(w in d['instruction'].replace('未规定每项只用一次','') for w in ['限用一次', '只用一次', '只能用一次'])
        for row in d['slots']:
            assert row['answer'] in candidates and set(row['grounds']) == set(candidates)
            assert all(row['grounds'].values())
    return True


def compile_author(manuscript):
    d = json.loads(manuscript.read_text())
    bp = load_ref(d['source_bindings'])
    b = next(v for v in json.loads(bp.read_text())['bindings'] if v['id'] == d['source_binding'])
    s = next(v for v in json.loads(load_ref(b['source_index']).read_text())['groups'] if v['id'] == b['source_group_id'])
    validate(d, s)
    given = d['mode'] == 'given_forms5'
    tasks, extra = [], {}
    if given:
        for n,r in enumerate(d['sentences'],1):
            tasks.append(dict(number=n, stem=r['frame']+' ('+r['lemma']+')', options=[], givenLemma=r['lemma'],
                acceptedAnswers=r['accepted'], fillMarking=dict(version=1, review='author_context_checked',
                    normalization='english_phrase_v1', maxWords=None, unlisted='review', unknownSyntax='review',
                    rejectedAnswers=list(r['rejected'])),
                rationale='；'.join(k+'：'+v for k,v in {**r['grounds'],**r['rejected']}.items())+
                    '；未列出的形式尚未穷尽核实，显示待复核，不据此断言错误。'))
        filled = [[r['frame'].replace('____',v) for r,v in zip(d['sentences'],values)]
                  for values in product(*(r['accepted'] for r in d['sentences']))]
        passage = ''
        body = ''
        extra.update(given_forms5=True, fully_filled_sentence_sets=filled,
                     full_fill_variant_combinations=len(filled), variant_evidence=d['variant_evidence'])
        full = '\n\n'.join('\n'.join(rows) for rows in filled)
    else:
        passage = d['passage']
        bank = dict(d['shared_candidates'])
        filled = passage
        pairs = []
        for n,r in enumerate(d['slots'],1):
            tasks.append(dict(number=n, stem='第'+str(n)+'空', options=d['shared_candidates'], answer=r['answer'],
                rationale='；'.join(k+'：'+v for k,v in r['grounds'].items())))
            filled = filled.replace('('+str(n)+') ____',bank[r['answer']])
            for k,v in d['shared_candidates']:
                test = passage
                for i,row in enumerate(d['slots'],1):
                    test = test.replace('('+str(i)+') ____',v if i==n else bank[row['answer']])
                pairs.append(dict(number=n,candidate=k,is_best=k==r['answer'],reason=r['grounds'][k],full_group_substitution=test))
        body = passage+'\n\n### 共享候选\n\n'+'\n\n'.join(k+'. '+v for k,v in d['shared_candidates'])+'\n\n'
        full = filled
        extra.update(dialogue_clauses5=True, shared_candidates=d['shared_candidates'], filled_passage=filled,
                     choice_pair_audit=pairs, reuse_rule='not_explicit')
    block = response_markdown(tasks)
    p = manuscript.parent / (d['id']+'-v0.1.md')
    ap = manuscript.parent / (d['id']+'-author-check-v0.1.json')
    teacher = '\n\n'.join('### '+str(q['number'])+'：'+(' / '.join(q['acceptedAnswers']) if given else q['answer'])+'\n\n'+q['rationale'] for q in tasks)
    candidate_text = ('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+
        '<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+
        '\n\n### 完整回填\n\n'+full+'\n\n'+d['source_notice']+'\n')
    if p.exists():
        assert p.read_text() == candidate_text, 'Frozen candidate differs; create a new version'
    else:
        p.write_text(candidate_text)
    a = dict(version='0.1', id=d['id'], grade=d['grade'], questions=5, candidate_sha256=ref(p)['sha256'],
        source_binding=b['id'], source_bindings=ref(bp), source_group_id=s['id'], manuscript=ref(manuscript),
        review_response_tasks=tasks, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),
        student_passage=passage, source_count_increment=0, authored_student_inputs_complete=True,
        independent_teacher_student_commercial_production_validated=False,
        load_measure=dict(body_English_words=words(passage), stem_English_words=sum(words(q['stem']) for q in tasks),
            options_English_words_with_repeated_bank=sum(words(v) for q in tasks for _,v in q['options']),
            output_response_positions=5, **(dict(output_known_form_word_counts=[[len(v.split()) for v in r['accepted']] for r in d['sentences']]) if given else
                dict(options_English_words_unique_bank=sum(words(v) for _,v in d['shared_candidates'])))), **extra)
    audit_text = json.dumps(a, ensure_ascii=False, indent=2)+'\n'
    if ap.exists():
        assert ap.read_text() == audit_text, 'Frozen audit differs; create a new version'
    else:
        ap.write_text(audit_text)
    return dict(id=d['id'], grade='primary6', family=d['family'],
        family_label='句中语法/词形填空' if given else '共享候选对话补全', title=d['title'], questions=5,
        candidate=ref(p), author_check=ref(ap), source_group_ids=[s['id']], instruction=d['instruction'],
        source_form_notice=d['source_notice'], **({} if given else dict(use_select_controls=True)),
        format_summary='5独立句 / 每句给词 / 每空不限一词 / 已核变体同等接受，未列形式待复核' if given else
            '1完整对话 / 2说话人7轮 / 5空5共享候选 / 两问句三连词起始分句 / 未明示每项一次')


def check(g,a,b,s):
    d = json.loads(load_ref(a['manuscript']).read_text())
    validate(d,s)
    selected = json.loads(load_ref(s['selected_native']).read_text())
    native = json.loads(load_ref(selected['native_text']).read_text())
    assert selected['configuration'] == b['source_features'] == s['features']
    assert selected['source'] == s['source'] and selected['source_key_acquired'] is False
    for span in selected['spans']:
        block = native['pages'][span['physical_page']-1]['text'][span['start']:span['end']]
        assert block == span['text'] and hashlib.sha256(block.encode()).hexdigest() == span['sha256']
    assert b['responses'] == a['questions'] == len(g['questions']) == 5
    if d['mode'] == 'given_forms5':
        assert a['given_forms5'] and b['options_each'] == 0
        assert '每空不限填一词' in selected['spans'][0]['text']
        for q,r in zip(g['questions'], d['sentences']):
            assert q['stem'] == r['frame']+' ('+r['lemma']+')' and q['givenLemma'] == r['lemma']
            assert q['acceptedAnswers'] == r['accepted'] and q['options'] == []
            assert q['fillMarking']['maxWords'] is None
            assert q['fillMarking']['unknownSyntax'] == q['fillMarking']['unlisted'] == 'review'
            assert q['fillMarking']['rejectedAnswers'] == list(r['rejected'])
            assert q['fillMarking']['normalization'] == 'english_phrase_v1'
        filled = [[r['frame'].replace('____',v) for r,v in zip(d['sentences'],values)]
                  for values in product(*(r['accepted'] for r in d['sentences']))]
        assert a['fully_filled_sentence_sets'] == filled and a['full_fill_variant_combinations'] == len(filled)
    else:
        assert a['dialogue_clauses5'] and g['fixedSharedBank'] and b['options_each'] == 5
        assert a['reuse_rule'] == b['reuse_rule'] == 'not_explicit'
        assert len(a['choice_pair_audit']) == 25 and a['shared_candidates'] == d['shared_candidates']
        filled = d['passage']
        for n,r in enumerate(d['slots'],1):
            q = g['questions'][n-1]
            assert q['options'] == d['shared_candidates'] and q['answer'] == r['answer'] and 'bankReuse' not in q
            filled = filled.replace('('+str(n)+') ____',dict(d['shared_candidates'])[r['answer']])
        assert a['filled_passage'] == filled and '____' not in filled
        assert {(p['number'],p['candidate']) for p in a['choice_pair_audit']} == {(n,k) for n in range(1,6) for k in 'ABCDE'}
        for p in a['choice_pair_audit']:
            expected = d['passage']
            for n,r in enumerate(d['slots'],1):
                expected = expected.replace('('+str(n)+') ____',dict(d['shared_candidates'])[p['candidate'] if n==p['number'] else r['answer']])
            assert p['full_group_substitution'] == expected and p['is_best'] == (d['slots'][p['number']-1]['answer']==p['candidate'])
            assert p['reason'] == d['slots'][p['number']-1]['grounds'][p['candidate']]
    return True
