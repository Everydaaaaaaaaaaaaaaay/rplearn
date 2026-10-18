"""Ten four-option decisions, preserving a two-blank joint-choice item."""
import hashlib
import json
import re
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown


def ref(path):
    path = path.resolve()
    return {'path': str(path.relative_to(BASE) if path.is_relative_to(BASE) else path.relative_to(REPO)),
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def validate(draft, source):
    assert draft['source_group_id'] == source['id']
    assert draft['grade'] == source['level'] == 'primary6'
    assert draft['family'] == source['kind'] == 'sentence_choice'
    assert source['features'] == dict(sentence_tasks=10, responses=10, options_each=4,
        visible_blank_slots_each=[1,1,1,1,2,1,1,1,1,1], joint_choice_positions=[5],
        shared_bank=False, response_mode='one_letter_each', necessary_audio=False, necessary_images=False)
    assert len(draft['items']) == 10
    for n, row in enumerate(draft['items'], 1):
        assert row['stem'].count('____') == (2 if n == 5 else 1)
        assert len(row['options']) == len({' '.join(value.split()).casefold() for value in row['options']}) == len(row['grounds']) == 4
        assert row['key'] in list('ABCD') and all(row['grounds'])
        if n == 5:
            assert all(len(value.split(', ')) == 2 for value in row['options'])
    return True


def check(group, audit, binding, source):
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    validate(draft, source)
    selected = json.loads(load_ref(source['selected_native']).read_text())
    assert selected['source'] == source['source'] and selected['physical_page'] == 1
    native = json.loads(load_ref(selected['native_text']).read_text())['pages'][0]['text']
    block = native[native.index('1.'):native.index('11.')]
    assert selected['source_block_text'] == block
    assert hashlib.sha256(block.encode()).hexdigest() == selected['source_block_sha256']
    # Native export puts A-D on the same line, before each stem.
    assert len(re.findall(r'(?<![A-Za-z])[ABCD]\. ', block)) == 40
    assert len(selected['items']) == 10
    assert [r['visible_blanks'] for r in selected['items']] == source['features']['visible_blank_slots_each']
    assert source['source_key_acquired'] is False and source['school_exam_authentication'] is False
    assert binding['responses'] == audit['questions'] == len(group['questions']) == 10
    assert binding['source_features'] == source['features'] and binding['options_each'] == 4
    assert len(audit['candidate_reason_rows']) == 10 and audit['joint_decision_positions'] == [5]
    assert sum(q['stem'].count('____') for q in group['questions']) == 11
    for q, row, reasons in zip(group['questions'], draft['items'], audit['candidate_reason_rows']):
        assert q['stem'] == row['stem'] and q['options'] == [list(p) for p in zip('ABCD', row['options'])]
        assert q['answer'] == row['key'] and q['rationale'] == '；'.join(label+'：'+why for label, why in zip('ABCD', row['grounds']))
        assert reasons == dict(number=q['number'], key=row['key'], grounds=dict(zip('ABCD', row['grounds'])))
    return True


def compile_author(manuscript):
    draft = json.loads(manuscript.read_text())
    binding_path = load_ref(draft['source_bindings'])
    binding = next(r for r in json.loads(binding_path.read_text())['bindings'] if r['id'] == draft['source_binding'])
    source = next(r for r in json.loads(load_ref(binding['source_index']).read_text())['groups'] if r['id'] == binding['source_group_id'])
    validate(draft, source)
    tasks = [dict(number=n, stem=row['stem'], options=[list(p) for p in zip('ABCD', row['options'])], answer=row['key'],
                  rationale='；'.join(label+'：'+why for label, why in zip('ABCD', row['grounds'])))
             for n, row in enumerate(draft['items'], 1)]
    block = response_markdown(tasks)
    candidate = manuscript.parent / (draft['id']+'-v0.1.md')
    audit_path = manuscript.parent / (draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not audit_path.exists()
    teacher = '\n\n'.join('### '+str(q['number'])+'：'+q['answer']+'\n\n'+q['rationale'] for q in tasks)
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n\n'+draft['source_notice']+'\n')
    audit = dict(version='0.1', id=draft['id'], grade='primary6', questions=10, source_binding=binding['id'],
        source_bindings=ref(binding_path), source_group_id=source['id'], candidate_sha256=ref(candidate)['sha256'],
        manuscript=ref(manuscript), canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),
        review_response_tasks=tasks, student_passage='', ten_sentence_four_choices=True, joint_decision_positions=[5],
        candidate_reason_rows=[dict(number=q['number'], key=q['answer'], grounds=dict(zip('ABCD', row['grounds']))) for q, row in zip(tasks, draft['items'])],
        source_count_increment=0, source_key_not_copied=True, authored_student_inputs_complete=True,
        independent_teacher_student_commercial_production_validated=False,
        load_measure=dict(body_English_words=0, stem_English_words=sum(words(q['stem']) for q in tasks),
            options_English_words_with_repeated_bank=sum(words(t) for q in tasks for _, t in q['options']),
            output_response_positions=10, visible_blank_slots=11, output_letter_count=10))
    audit_path.write_text(json.dumps(audit, ensure_ascii=False, indent=2)+'\n')
    return dict(id=draft['id'], grade='primary6', family='sentence_choice', family_label='独立句单选', title=draft['title'],
        questions=10, candidate=ref(candidate), author_check=ref(audit_path), source_group_ids=[source['id']],
        instruction=draft['instruction'], source_form_notice=draft['source_notice'],
        format_summary='10道独立四选题 / 第5题两空联选一个组合 / 共11个题面空、10个选择回应 / 无共享词库')
