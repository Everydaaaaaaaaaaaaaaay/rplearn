"""Whole sentence groups with printed local candidate pairs and written answers."""
import hashlib
import json
import re
from itertools import product
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown


def ref(path):
    path = path.resolve()
    return {'path': str(path.relative_to(BASE) if path.is_relative_to(BASE) else path.relative_to(REPO)),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def words(value):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", value))


def validate(draft, source):
    assert draft['source_group_id'] == source['id']
    assert draft['grade'] == source['level'] == 'primary6'
    assert draft['family'] == source['kind'] == 'sentence_form'
    assert source['features'] == dict(sentence_tasks=10, responses=10, candidates_each=2,
        shared_candidates=False, response_mode='write_selected_word_or_phrase',
        candidate_word_counts=[[1, 1]] * 4 + [[2, 2]] + [[1, 1]] * 2 + [[2, 1]] + [[1, 1]] * 2,
        source_max_words_each=None, necessary_audio=False, necessary_images=False)
    assert len(draft['sentences']) == 10
    for row, counts in zip(draft['sentences'], source['features']['candidate_word_counts']):
        assert row['frame'].count('____') == 1 and '(' not in row['frame']
        assert len(row['candidates']) == len(set(v.casefold() for v in row['candidates'])) == 2
        assert [len(v.split()) for v in row['candidates']] == counts
        assert row['accepted'] and len(row['accepted']) == len(set(row['accepted']))
        assert set(row['accepted']) <= set(row['candidates'])
        assert len(row['grounds']) == 2 and all(row['grounds'])
        assert all(re.fullmatch('[A-Za-z]+(?: [A-Za-z]+)*', v) for v in row['candidates'])
    usage = json.loads(load_ref(draft['learn_variants_evidence']).read_text())
    assert usage['past_simple_forms'] == ['learned', 'learnt']
    assert usage['publisher'] == 'Oxford University Press'
    for row in draft['sentences']:
        if set(row['candidates']) == {'learned', 'learnt'}:
            assert set(row['accepted']) == {'learned', 'learnt'}
    return True


def check(group, audit, binding, source):
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    validate(draft, source)
    selected = json.loads(load_ref(source['selected_native']).read_text())
    assert selected['source'] == source['source'] and selected['physical_page'] == 2
    assert selected['whole_section_number'] == 12 and len(selected['items']) == 10
    assert selected['instruction'] == '选词或词组填空，将正确的答案填在横线上。'
    native = json.loads(load_ref(selected['native_text']).read_text())['pages'][1]['text']
    block = native[native.index('12.'):native.index('13.')]
    assert selected['source_block_text'] == block
    assert selected['source_block_sha256'] == hashlib.sha256(block.encode()).hexdigest()
    assert selected['instruction'] in block
    pairs = [[left.strip(), right.strip()] for left, right in re.findall(r'\(([^(),]+),([^(),]+)\)', block)]
    assert pairs == [r['candidates'] for r in selected['items']]
    assert [len(r['candidates']) for r in selected['items']] == [2] * 10
    assert [[len(v.split()) for v in r['candidates']] for r in selected['items']] == source['features']['candidate_word_counts']
    assert binding['responses'] == len(group['questions']) == 10
    assert audit['paired_word_fill'] and binding['options_each'] == 0
    assert binding['source_features'] == source['features']
    assert source['source_printed_inputs_complete'] and source['source_key_acquired'] is False
    assert source['source_original_key_not_gold'] is True and source['school_exam_authentication'] is False
    for q, row in zip(group['questions'], draft['sentences']):
        assert q['stem'] == row['frame'] + ' (' + ' / '.join(row['candidates']) + ')'
        assert q['givenCandidates'] == row['candidates'] and q['acceptedAnswers'] == row['accepted']
        assert q['options'] == [] and q['fillMarking']['normalization'] == 'english_phrase_v1'
        assert q['fillMarking']['closedCandidates'] is True and q['fillMarking']['maxWords'] is None
        assert q['fillMarking']['unknownSyntax'] == q['fillMarking']['unlisted'] == 'review'
        assert q['fillMarking']['rejectedAnswers'] == [v for v in row['candidates'] if v not in row['accepted']]
    expected = [[row['frame'].replace('____', value) for row, value in zip(draft['sentences'], answers)]
                for answers in product(*(r['accepted'] for r in draft['sentences']))]
    assert audit['fully_filled_sentence_sets'] == expected
    assert audit['full_fill_variant_combinations'] == len(expected)
    return True


def compile_author(manuscript):
    d = json.loads(manuscript.read_text())
    bp = load_ref(d['source_bindings'])
    b = next(r for r in json.loads(bp.read_text())['bindings'] if r['id'] == d['source_binding'])
    s = next(r for r in json.loads(load_ref(b['source_index']).read_text())['groups'] if r['id'] == b['source_group_id'])
    validate(d, s)
    tasks = []
    for n, row in enumerate(d['sentences'], 1):
        tasks.append(dict(number=n, stem=row['frame']+' ('+' / '.join(row['candidates'])+')', options=[],
            givenCandidates=row['candidates'], acceptedAnswers=row['accepted'],
            fillMarking=dict(version=1, review='author_context_checked', normalization='english_phrase_v1',
                maxWords=None, unlisted='review', unknownSyntax='review', closedCandidates=True,
                rejectedAnswers=[v for v in row['candidates'] if v not in row['accepted']]),
            rationale='；'.join(v+'：'+why for v, why in zip(row['candidates'], row['grounds']))))
    filled = [[r['frame'].replace('____', v) for r, v in zip(d['sentences'], values)]
              for values in product(*(r['accepted'] for r in d['sentences']))]
    block = response_markdown(tasks)
    p = manuscript.parent / (d['id']+'-v0.1.md')
    ap = manuscript.parent / (d['id']+'-author-check-v0.1.json')
    assert not p.exists() and not ap.exists()
    teacher = '\n\n'.join('### '+str(q['number'])+'：'+' / '.join(q['acceptedAnswers'])+'\n\n'+q['rationale'] for q in tasks)
    teacher += '\n\n### 完整合法回填\n\n'+'\n\n'.join('\n'.join(rows) for rows in filled)+'\n\n'+d['source_notice']
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    a = dict(version='0.1', id=d['id'], grade=d['grade'], questions=10, candidate_sha256=ref(p)['sha256'],
        source_binding=b['id'], source_bindings=ref(bp), source_group_id=s['id'], manuscript=ref(manuscript),
        paired_word_fill=True, review_response_tasks=tasks, canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),
        student_passage='', fully_filled_sentence_sets=filled, full_fill_variant_combinations=len(filled),
        source_count_increment=0, authored_student_inputs_complete=True, independent_teacher_student_commercial_production_validated=False,
        load_measure=dict(body_English_words=0, stem_English_words=sum(words(q['stem']) for q in tasks),
            options_English_words_with_repeated_bank=0, output_response_positions=10,
            sentence_context_English_words=sum(words(r['frame']) for r in d['sentences']),
            printed_local_candidates_English_words=sum(words(v) for r in d['sentences'] for v in r['candidates']),
            output_word_counts=[len(r['accepted'][0].split()) for r in d['sentences']] ))
    ap.write_text(json.dumps(a, ensure_ascii=False, indent=2)+'\n')
    return dict(id=d['id'], grade=d['grade'], family=d['family'], family_label='句中语法/词形填空', title=d['title'],
        questions=10, candidate=ref(p), author_check=ref(ap), source_group_ids=[s['id']], instruction=d['instruction'],
        source_form_notice=d['source_notice'], format_summary='10独立句 / 每空2个给定候选 / 填词或词组，不填字母 / 候选不变形 / 无共享词库')
